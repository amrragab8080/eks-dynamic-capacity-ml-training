variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "pytorch-training-cluster"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "karpenter_version" {
  description = "Karpenter version"
  type        = string
  default     = "1.0.1"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.34"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}
