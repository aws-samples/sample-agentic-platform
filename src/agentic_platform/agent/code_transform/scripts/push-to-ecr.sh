#!/bin/bash
#
# push-to-ecr.sh - Tag and push ATX Container Test Runner image to Amazon ECR
#
# This script handles:
# - ECR authentication
# - Image tagging with version and latest tags
# - Pushing to ECR repository
# - Verification of successful push
#
# Usage:
#   ./push-to-ecr.sh <aws-account-id> <region> [repository-name] [version]
#
# Example:
#   ./push-to-ecr.sh 123456789012 us-east-1
#   ./push-to-ecr.sh 123456789012 us-east-1 atx-test-runner 0.1.0
#

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DEFAULT_REPO_NAME="atx-test-runner"
DEFAULT_VERSION=$(cat VERSION 2>/dev/null || echo "0.1.0")

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 <aws-account-id> <region> [repository-name] [version]

Arguments:
  aws-account-id    AWS account ID (required)
  region            AWS region (required, e.g., us-east-1)
  repository-name   ECR repository name (optional, default: ${DEFAULT_REPO_NAME})
  version           Image version tag (optional, default: ${DEFAULT_VERSION})

Examples:
  $0 123456789012 us-east-1
  $0 123456789012 us-east-1 atx-test-runner 0.2.0

Environment Variables:
  AWS_PROFILE       AWS CLI profile to use (optional)
  AWS_REGION        AWS region (overridden by command line argument)

Prerequisites:
  - AWS CLI installed and configured
  - Docker installed and running
  - Appropriate IAM permissions for ECR operations
  - ECR repository must exist (or use --create-repo flag)

EOF
    exit 1
}

# Parse command line arguments
if [ $# -lt 2 ]; then
    log_error "Missing required arguments"
    usage
fi

AWS_ACCOUNT_ID="$1"
AWS_REGION="$2"
REPO_NAME="${3:-${DEFAULT_REPO_NAME}}"
VERSION="${4:-${DEFAULT_VERSION}}"

# Validate AWS account ID format
if ! [[ "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
    log_error "Invalid AWS account ID format. Must be 12 digits."
    exit 1
fi

# Construct ECR repository URI
ECR_REPO_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}"

log_info "Starting ECR push process..."
log_info "AWS Account: ${AWS_ACCOUNT_ID}"
log_info "Region: ${AWS_REGION}"
log_info "Repository: ${REPO_NAME}"
log_info "Version: ${VERSION}"
log_info "ECR URI: ${ECR_REPO_URI}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    log_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if local image exists
LOCAL_IMAGE="${REPO_NAME}:latest"
if ! docker image inspect "${LOCAL_IMAGE}" > /dev/null 2>&1; then
    log_error "Local image '${LOCAL_IMAGE}' not found. Please build the image first."
    log_info "Run: docker build -t ${LOCAL_IMAGE} ."
    exit 1
fi

# Authenticate Docker to ECR
log_info "Authenticating Docker to ECR..."
if aws ecr get-login-password --region "${AWS_REGION}" | \
   docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"; then
    log_info "Successfully authenticated to ECR"
else
    log_error "Failed to authenticate to ECR"
    exit 1
fi

# Check if ECR repository exists
log_info "Checking if ECR repository exists..."
if aws ecr describe-repositories --repository-names "${REPO_NAME}" --region "${AWS_REGION}" > /dev/null 2>&1; then
    log_info "ECR repository '${REPO_NAME}' exists"
else
    log_warn "ECR repository '${REPO_NAME}' does not exist"
    log_info "Creating ECR repository..."
    if aws ecr create-repository \
        --repository-name "${REPO_NAME}" \
        --region "${AWS_REGION}" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 > /dev/null 2>&1; then
        log_info "Successfully created ECR repository"
    else
        log_error "Failed to create ECR repository"
        exit 1
    fi
fi

# Tag the image with version
log_info "Tagging image with version ${VERSION}..."
docker tag "${LOCAL_IMAGE}" "${ECR_REPO_URI}:${VERSION}"
docker tag "${LOCAL_IMAGE}" "${ECR_REPO_URI}:latest"

# Push version tag
log_info "Pushing image with version tag ${VERSION}..."
if docker push "${ECR_REPO_URI}:${VERSION}"; then
    log_info "Successfully pushed ${ECR_REPO_URI}:${VERSION}"
else
    log_error "Failed to push version tag"
    exit 1
fi

# Push latest tag
log_info "Pushing image with latest tag..."
if docker push "${ECR_REPO_URI}:latest"; then
    log_info "Successfully pushed ${ECR_REPO_URI}:latest"
else
    log_error "Failed to push latest tag"
    exit 1
fi

# Verify the image is accessible
log_info "Verifying image is accessible in ECR..."
if aws ecr describe-images \
    --repository-name "${REPO_NAME}" \
    --image-ids imageTag="${VERSION}" \
    --region "${AWS_REGION}" > /dev/null 2>&1; then
    log_info "Successfully verified image ${VERSION} in ECR"
else
    log_error "Failed to verify image in ECR"
    exit 1
fi

# Get image details
IMAGE_DIGEST=$(aws ecr describe-images \
    --repository-name "${REPO_NAME}" \
    --image-ids imageTag="${VERSION}" \
    --region "${AWS_REGION}" \
    --query 'imageDetails[0].imageDigest' \
    --output text)

IMAGE_SIZE=$(aws ecr describe-images \
    --repository-name "${REPO_NAME}" \
    --image-ids imageTag="${VERSION}" \
    --region "${AWS_REGION}" \
    --query 'imageDetails[0].imageSizeInBytes' \
    --output text)

IMAGE_SIZE_MB=$((IMAGE_SIZE / 1024 / 1024))

# Print summary
echo ""
log_info "=========================================="
log_info "ECR Push Summary"
log_info "=========================================="
log_info "Repository URI: ${ECR_REPO_URI}"
log_info "Version Tag: ${VERSION}"
log_info "Latest Tag: latest"
log_info "Image Digest: ${IMAGE_DIGEST}"
log_info "Image Size: ${IMAGE_SIZE_MB} MB"
log_info "=========================================="
echo ""
log_info "Image successfully pushed to ECR!"
echo ""
log_info "To pull this image:"
echo "  docker pull ${ECR_REPO_URI}:${VERSION}"
echo "  docker pull ${ECR_REPO_URI}:latest"
echo ""
log_info "To use in ECS task definition:"
echo "  \"image\": \"${ECR_REPO_URI}:${VERSION}\""
echo ""

exit 0
