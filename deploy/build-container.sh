#!/bin/bash

# Check if container type is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <service-name>"
    echo "Available services are directories in the docker/ folder"
    exit 1
fi

SERVICE_NAME="$1"

# Move to project root
cd "$(dirname "$0")/.."

# Check for Dockerfile in src directory structure first, then fall back to docker directory
SRC_DOCKERFILE_PATH="src/agentic_platform/agent/${SERVICE_NAME}/Dockerfile"
DOCKER_DIR="docker/${SERVICE_NAME}"
DOCKER_DOCKERFILE_PATH="${DOCKER_DIR}/Dockerfile"

if [[ -f "$SRC_DOCKERFILE_PATH" ]]; then
    DOCKERFILE_PATH="$SRC_DOCKERFILE_PATH"
    echo "Using Dockerfile from src directory: $DOCKERFILE_PATH"
elif [[ -f "$DOCKER_DOCKERFILE_PATH" ]]; then
    DOCKERFILE_PATH="$DOCKER_DOCKERFILE_PATH"
    echo "Using Dockerfile from docker directory: $DOCKERFILE_PATH"
else
    echo "Error: Dockerfile not found at $SRC_DOCKERFILE_PATH or $DOCKER_DOCKERFILE_PATH"
    echo "Available services in docker/:"
    ls -1 docker/ 2>/dev/null | grep -v "^$" || echo "  No services found in docker/ directory"
    echo "Available services in src/agentic_platform/agent/:"
    ls -1 src/agentic_platform/agent/ 2>/dev/null | grep -v "^$" || echo "  No services found in src/agentic_platform/agent/ directory"
    exit 1
fi

# Configuration - handle both local and CI environments
if [[ -n "$AWS_REGION" ]]; then
    # Use environment variable (GitHub Actions)
    echo "Using AWS_REGION from environment: $AWS_REGION"
elif command -v aws &> /dev/null && aws configure get region &> /dev/null; then
    # Use AWS CLI config (local development)
    AWS_REGION=$(aws configure get region)
    echo "Using AWS_REGION from AWS CLI config: $AWS_REGION"
else
    # Default fallback
    AWS_REGION="us-east-1"
    echo "Using default AWS_REGION: $AWS_REGION"
fi

# Validate AWS_REGION is not empty
if [[ -z "$AWS_REGION" ]]; then
    echo "Error: AWS_REGION is empty"
    exit 1
fi

ECR_REPO_NAME="agentic-platform-${SERVICE_NAME}"  # Repository name based on service
IMAGE_TAG="latest"  # Using latest tag

# Get AWS account ID - handle both local and CI
if command -v aws &> /dev/null; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
else
    echo "Error: AWS CLI not available"
    exit 1
fi

# Validate AWS_ACCOUNT_ID
if [[ -z "$AWS_ACCOUNT_ID" || "$AWS_ACCOUNT_ID" == "None" ]]; then
    echo "Error: Could not determine AWS Account ID"
    exit 1
fi

ECR_REPO_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME"

echo "Configuration:"
echo "  AWS_REGION: $AWS_REGION"
echo "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
echo "  ECR_REPO_NAME: $ECR_REPO_NAME"
echo "  ECR_REPO_URI: $ECR_REPO_URI"

# Authenticate Docker with ECR
echo "Authenticating with ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

if [ $? -ne 0 ]; then
    echo "Error: Failed to authenticate with ECR"
    exit 1
fi

# Create ECR repository if it doesn't exist
echo "Ensuring ECR repository exists..."
if ! aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "Repository $ECR_REPO_NAME does not exist. Creating..."
    aws ecr create-repository --repository-name "$ECR_REPO_NAME" --region "$AWS_REGION"
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create ECR repository"
        exit 1
    fi
    echo "Repository $ECR_REPO_NAME created successfully"
else
    echo "Repository $ECR_REPO_NAME already exists"
fi

# Build Docker image
echo "Building Docker image..."
docker buildx build --platform linux/amd64,linux/arm64 -t "$ECR_REPO_URI:$IMAGE_TAG" -f "$DOCKERFILE_PATH" .

if [ $? -ne 0 ]; then
    echo "Error: Failed to build Docker image"
    exit 1
fi

# Push to ECR
echo "Pushing to ECR..."
docker push "$ECR_REPO_URI:$IMAGE_TAG"

if [ $? -ne 0 ]; then
    echo "Error: Failed to push to ECR"
    exit 1
fi

echo "Done! Image pushed to: $ECR_REPO_URI:$IMAGE_TAG"