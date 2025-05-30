#!/bin/bash

# Check if service name is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <service-name>"
    return 1
fi

SERVICE_NAME=$1

# Define the Terraform directory
TERRAFORM_DIR="infrastructure/terraform"

# Build and push the container
./deploy/build-container.sh $SERVICE_NAME

COGNITO_USER_POOL_ID=$(cd "$TERRAFORM_DIR" && terraform output -raw cognito_user_pool_id)
COGNITO_USER_CLIENT_ID=$(cd "$TERRAFORM_DIR" && terraform output -raw cognito_user_client_id)
COGNITO_M2M_CLIENT_ID=$(cd "$TERRAFORM_DIR" && terraform output -raw cognito_m2m_client_id)

# Get ECR URI for Helm
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
ECR_REPO_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/agentic-platform-${SERVICE_NAME}"

# Deploy with Helm
echo "Deploying to Kubernetes with Helm..."
helm upgrade --install $SERVICE_NAME ./k8s/helm/charts/agentic-service \
  --set image.repository=$ECR_REPO_URI \
  --set nameOverride=$SERVICE_NAME \
  --set serviceAccount.name=$SERVICE_NAME-sa \
  --set ingress.enabled=true \
  --set ingress.path="/$SERVICE_NAME" \
  --set config.ENVIRONMENT="dev" \
  --set config.LLM_GATEWAY_ENDPOINT="http://llm-gateway.default.svc.cluster.local:80" \
  --set config.RETRIEVAL_GATEWAY_ENDPOINT="http://retrieval-gateway.default.svc.cluster.local:80" \
  --set config.MEMORY_GATEWAY_ENDPOINT="http://memory-gateway.default.svc.cluster.local:80" \
  --set config.AWS_DEFAULT_REGION=$AWS_REGION \
  --set config.COGNITO_USER_POOL_ID=$COGNITO_USER_POOL_ID \
  --set config.COGNITO_USER_CLIENT_ID=$COGNITO_USER_CLIENT_ID \
  --set config.COGNITO_M2M_CLIENT_ID=$COGNITO_M2M_CLIENT_ID \

echo "Deployment complete!"
