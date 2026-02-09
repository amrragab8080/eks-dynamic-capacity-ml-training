# PyTorch Distributed Training with Karpenter Dynamic Node Provisioning

Terraform-based setup for EKS cluster with Karpenter autoscaling and dynamic distributed training jobs.

## Architecture

- EKS cluster in us-west-2 with g5.12xlarge instances (4 GPUs each)
- Karpenter NodePools with max node limits (small: 4 nodes, large: 16 nodes)
- Launcher pattern that counts actual provisioned nodes
- PyTorch DDP training adapts to available world size

## Prerequisites

- AWS CLI configured
- Terraform >= 1.6
- kubectl
- helm
- Docker (for building training image)

## Quick Start

```bash
# 1. Initialize Terraform
terraform init

# 2. Review plan
terraform plan

# 3. Create infrastructure
terraform apply

# 4. Configure kubectl
aws eks update-kubeconfig --name pytorch-training-cluster --region us-west-2

# 5. Create ECR repository and build training image
aws ecr create-repository --repository-name pytorch-training --region us-west-2
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-west-2.amazonaws.com

cd training-image
docker build -t pytorch-training .
docker tag pytorch-training:latest <account-id>.dkr.ecr.us-west-2.amazonaws.com/pytorch-training:latest
docker push <account-id>.dkr.ecr.us-west-2.amazonaws.com/pytorch-training:latest
cd ..

# 6. Configure launcher parameters
# Edit manifests/training-launcher-small.yaml or training-launcher-large.yaml
# Set MIN_NODES and MAX_NODES environment variables to control node provisioning range
# Example: MIN_NODES=2, MAX_NODES=4 will wait for 2-4 nodes and adapt training accordingly

# 7. Submit training job
kubectl apply -f manifests/training-launcher-small.yaml
# or
kubectl apply -f manifests/training-launcher-large.yaml
```

## Project Structure

```
.
├── main.tf                          # Main Terraform configuration
├── variables.tf                     # Input variables
├── outputs.tf                       # Outputs
├── versions.tf                      # Provider versions
├── terraform.tfvars                 # Variable values
├── modules/
│   ├── karpenter-config/            # Karpenter NodePools
│   └── kubeflow/                    # Kubeflow Training Operator
├── manifests/
│   ├── rbac.yaml                    # Service account and permissions
│   ├── training-launcher-small.yaml # Launcher for small jobs
│   └── training-launcher-large.yaml # Launcher for large jobs
└── training-image/
    ├── Dockerfile                   # PyTorch training container
    ├── train.py                     # PyTorch DDP MNIST example
    └── build.sh                     # Build and push script
```

## Configuration

Edit `terraform.tfvars`:
```hcl
cluster_name = "pytorch-training-cluster"
region       = "us-west-2"
```

## How It Works

1. User submits launcher Job (small or large)
2. Karpenter provisions GPU nodes up to NodePool limit
3. Launcher waits for nodes (handles insufficient capacity)
4. Launcher counts actual ready GPU nodes
5. Launcher submits PyTorchJob with exact replica count
6. PyTorch DDP training runs with adapted world size

## Cleanup

```bash
# Delete Kubernetes resources first
kubectl delete pytorchjobs --all
kubectl delete jobs --all

# Destroy infrastructure
terraform destroy
```
