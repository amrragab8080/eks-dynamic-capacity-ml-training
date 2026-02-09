# Build and push training image

# Update these values
REGISTRY="010438491516.dkr.ecr.us-west-2.amazonaws.com"
IMAGE_NAME="pytorchddp/basic"
TAG="latest"

# Build for x86_64 (amd64) architecture
docker buildx build --no-cache --platform linux/amd64 -t ${REGISTRY}/${IMAGE_NAME}:${TAG} --load .

# Push to ECR
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin ${REGISTRY}
docker push ${REGISTRY}/${IMAGE_NAME}:${TAG}

# Update the image in launcher YAML files
echo "Update TRAINING_IMAGE in manifests/training-launcher-*.yaml to: ${REGISTRY}/${IMAGE_NAME}:${TAG}"
