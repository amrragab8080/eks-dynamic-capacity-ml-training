provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = var.cluster_name
  }
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  eks_managed_node_groups = {
    "${var.cluster_name}" = {
      instance_types = ["m5.large"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2
      
      iam_role_use_name_prefix = false

      labels = {
        role = "system"
      }

      tags = {
        "karpenter.sh/discovery" = var.cluster_name
      }
    }
  }

  tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}

# Associate admin policy to cluster creator
resource "null_resource" "associate_admin_policy" {
  provisioner "local-exec" {
    command = <<-EOT
      aws eks associate-access-policy \
        --cluster-name ${module.eks.cluster_name} \
        --principal-arn ${data.aws_caller_identity.current.arn} \
        --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
        --access-scope type=cluster \
        --region ${var.region} || true
    EOT
  }

  depends_on = [module.eks]
}

# Karpenter
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name = module.eks.cluster_name

  enable_irsa                     = true
  irsa_oidc_provider_arn          = module.eks.oidc_provider_arn
  irsa_namespace_service_accounts = ["kube-system:karpenter"]

  create_node_iam_role = false
  node_iam_role_arn    = module.eks.eks_managed_node_groups["${var.cluster_name}"].iam_role_arn
  
  # Don't create access entry - already exists
  create_access_entry = false

  tags = {
    Environment = "training"
  }
}

resource "helm_release" "karpenter" {
  namespace        = "kube-system"
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_version
  create_namespace = false

  values = [
    <<-EOT
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${module.karpenter.iam_role_arn}
    EOT
  ]

  depends_on = [module.eks]
}

# Karpenter NodePools
module "karpenter_config" {
  source = "./modules/karpenter-config"

  cluster_name        = var.cluster_name
  node_role_arn       = module.eks.eks_managed_node_groups["${var.cluster_name}"].iam_role_arn
  kubernetes_version  = var.kubernetes_version
  
  depends_on = [helm_release.karpenter]
}

# NVIDIA Device Plugin
data "http" "nvidia_device_plugin" {
  url = "https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.16.2/deployments/static/nvidia-device-plugin.yml"
}

resource "kubectl_manifest" "nvidia_device_plugin" {
  yaml_body = replace(
    data.http.nvidia_device_plugin.response_body,
    "tolerations:\n      - key: nvidia.com/gpu\n        operator: Exists\n        effect: NoSchedule",
    "tolerations:\n      - key: nvidia.com/gpu\n        operator: Exists\n        effect: NoSchedule\n      - key: training-size\n        operator: Exists\n        effect: NoSchedule"
  )
  
  depends_on = [module.eks]
}

# Kubeflow Training Operator
module "kubeflow" {
  source = "./modules/kubeflow"

  cluster_name     = var.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint
  region           = var.region

  depends_on = [module.eks]
}

# RBAC for training launcher
resource "kubernetes_namespace" "gpu_provisioning" {
  metadata {
    name = "gpu-provisioning"
  }

  depends_on = [module.eks]
}

resource "kubernetes_service_account" "training_launcher" {
  metadata {
    name      = "training-launcher"
    namespace = "default"
  }

  depends_on = [module.eks]
}

resource "kubernetes_cluster_role" "training_launcher" {
  metadata {
    name = "training-launcher"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["create", "delete", "get"]
  }

  rule {
    api_groups = ["kubeflow.org"]
    resources  = ["pytorchjobs", "tfjobs", "mxjobs", "xgboostjobs", "mpijobs", "paddlejobs"]
    verbs      = ["create", "get", "list"]
  }

  depends_on = [module.eks]
}

resource "kubernetes_cluster_role_binding" "training_launcher" {
  metadata {
    name = "training-launcher"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.training_launcher.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.training_launcher.metadata[0].name
    namespace = "default"
  }

  depends_on = [module.eks]
}
