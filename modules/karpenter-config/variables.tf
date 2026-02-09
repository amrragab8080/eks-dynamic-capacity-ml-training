variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for Karpenter nodes"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
}
