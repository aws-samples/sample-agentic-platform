#!/bin/bash
set -e

# This script is designed for GitLab CI/CD
# It expects one parameter: service name
# Dockerfiles are located in src/agentic_platform/agent/{service}/Dockerfile

SERVICE_NAME="$1"

if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <service-name>"
    echo "Example: $0 memory-gateway"
    exit 1
fi

echo "Building service: $SERVICE_NAME"

# Convert hyphens to underscores for folder paths
FOLDER_NAME="${SERVICE_NAME//-/_}"

# Move to project root
cd "$(dirname "$0")/.."

# Try to find Dockerfile in multiple locations
DOCKERFILE_PATH=""

# Check src/agentic_platform/agent/ first
if [[ -f "src/agentic_platform/agent/${FOLDER_NAME}/Dockerfile" ]]; then
    DOCKERFILE_PATH="src/agentic_platform/agent/${FOLDER_NAME}/Dockerfile"
    BUILD_CONTEXT="."  # Use repository root as build context
    echo "Using Dockerfile from: $DOCKERFILE_PATH"
# Check src/agentic_platform/service/ as fallback
elif [[ -f "src/agentic_platform/service/${FOLDER_NAME}/Dockerfile" ]]; then
    DOCKERFILE_PATH="src/agentic_platform/service/${FOLDER_NAME}/Dockerfile"
    BUILD_CONTEXT="."  # Use repository root as build context
    echo "Using Dockerfile from: $DOCKERFILE_PATH"
# Check docker/ directory as last resort
elif [[ -f "docker/${FOLDER_NAME}/Dockerfile" ]]; then
    DOCKERFILE_PATH="docker/${FOLDER_NAME}/Dockerfile"
    BUILD_CONTEXT="."  # Use repository root as build context
    echo "Using Dockerfile from: $DOCKERFILE_PATH"
else
    echo "Error: Dockerfile not found for service: $SERVICE_NAME"
    echo "Searched locations:"
    echo "  - src/agentic_platform/agent/${FOLDER_NAME}/Dockerfile"
    echo "  - src/agentic_platform/service/${FOLDER_NAME}/Dockerfile"
    echo "  - docker/${FOLDER_NAME}/Dockerfile"
    exit 1
fi

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPO_NAME="agentic-platform-${SERVICE_NAME}"
IMAGE_TAG="${CI_COMMIT_SHORT_SHA:-latest}"

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [[ -z "$AWS_ACCOUNT_ID" || "$AWS_ACCOUNT_ID" == "None" ]]; then
    echo "Error: Could not determine AWS Account ID"
    exit 1
fi

ECR_REPO_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME"

echo "Configuration:"
echo "  Service: $SERVICE_NAME"
echo "  Dockerfile: $DOCKERFILE_PATH"
echo "  Build Context: $BUILD_CONTEXT"
echo "  AWS Region: $AWS_REGION"
echo "  AWS Account: $AWS_ACCOUNT_ID"
echo "  ECR Repository: $ECR_REPO_NAME"
echo "  Image Tag: $IMAGE_TAG"

# Authenticate with ECR
echo "Authenticating with ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

if [ $? -ne 0 ]; then
    echo "Error: Failed to authenticate with ECR"
    exit 1
fi

# Create ECR repository if it doesn't exist
echo "Ensuring ECR repository exists..."
if ! aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "Creating ECR repository: $ECR_REPO_NAME"
    aws ecr create-repository --repository-name "$ECR_REPO_NAME" --region "$AWS_REGION"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create ECR repository"
        exit 1
    fi
else
    echo "ECR repository already exists: $ECR_REPO_NAME"
fi

# Build Docker image
echo "Building Docker image..."
docker build \
    -t "$ECR_REPO_URI:$IMAGE_TAG" \
    -t "$ECR_REPO_URI:latest" \
    -f "$DOCKERFILE_PATH" \
    "$BUILD_CONTEXT"

if [ $? -ne 0 ]; then
    echo "Error: Docker build failed"
    exit 1
fi

# Push images to ECR
echo "Pushing images to ECR..."
docker push "$ECR_REPO_URI:$IMAGE_TAG"
docker push "$ECR_REPO_URI:latest"

if [ $? -ne 0 ]; then
    echo "Error: Failed to push to ECR"
    exit 1
fi

echo "✅ Success! Images pushed to ECR:"
echo "  - $ECR_REPO_URI:$IMAGE_TAG"
echo "  - $ECR_REPO_URI:latest"
