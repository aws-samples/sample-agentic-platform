#!/bin/bash

# AWS OIDC Setup Script for GitLab CI/CD
# This script configures AWS to trust GitLab as an OIDC identity provider

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"
GITLAB_PROJECT_PATH="${1}"
ROLE_NAME="${2:-GitLabCIRole}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Validate inputs
if [ -z "$GITLAB_PROJECT_PATH" ]; then
    echo -e "${RED}Error: GitLab project path required${NC}"
    echo ""
    echo "Usage: $0 <gitlab-project-path> [role-name]"
    echo ""
    echo "Example: $0 mygroup/myproject GitLabCIRole"
    echo ""
    echo "Environment variables:"
    echo "  GITLAB_URL - GitLab instance URL (default: https://gitlab.com)"
    echo "  AWS_REGION - AWS region (default: us-east-1)"
    exit 1
fi

echo -e "${BLUE}=== AWS OIDC Setup for GitLab CI/CD ===${NC}"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "  GitLab URL: ${GITLAB_URL}"
echo "  Project Path: ${GITLAB_PROJECT_PATH}"
echo "  Role Name: ${ROLE_NAME}"
echo "  AWS Region: ${AWS_REGION}"
echo ""

# Check AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not found. Please install it first.${NC}"
    exit 1
fi

# Check AWS credentials are configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured. Please run 'aws configure' first.${NC}"
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}AWS Account ID: ${AWS_ACCOUNT_ID}${NC}"
echo ""

# Extract GitLab domain from URL
GITLAB_DOMAIN=$(echo "$GITLAB_URL" | sed 's|https://||' | sed 's|http://||' | sed 's|/.*||')

# Step 1: Create OIDC Identity Provider
echo -e "${GREEN}Step 1: Creating OIDC Identity Provider...${NC}"

OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${GITLAB_DOMAIN}"

# Check if provider already exists
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" &> /dev/null; then
    echo -e "${YELLOW}  OIDC provider already exists: ${OIDC_PROVIDER_ARN}${NC}"
else
    # Get GitLab's thumbprint
    echo -e "${BLUE}  Fetching GitLab OIDC thumbprint...${NC}"
    
    # For gitlab.com, use the known thumbprint
    if [ "$GITLAB_DOMAIN" = "gitlab.com" ]; then
        THUMBPRINT="1b511abead59c6ce207077c0bf0e0043b1382612"
    else
        # For self-hosted GitLab, calculate thumbprint
        THUMBPRINT=$(echo | openssl s_client -servername "$GITLAB_DOMAIN" -connect "${GITLAB_DOMAIN}:443" 2>/dev/null | \
                     openssl x509 -fingerprint -sha1 -noout | \
                     cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')
    fi
    
    echo -e "${BLUE}  Thumbprint: ${THUMBPRINT}${NC}"
    
    # Create the OIDC provider
    aws iam create-open-id-connect-provider \
        --url "${GITLAB_URL}" \
        --client-id-list "${GITLAB_URL}" \
        --thumbprint-list "${THUMBPRINT}" \
        --region "${AWS_REGION}"
    
    echo -e "${GREEN}  ✓ OIDC provider created${NC}"
fi

echo ""

# Step 2: Create IAM Role with Trust Policy
echo -e "${GREEN}Step 2: Creating IAM Role with Trust Policy...${NC}"

# Create trust policy document
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${GITLAB_DOMAIN}:aud": "${GITLAB_URL}"
        },
        "StringLike": {
          "${GITLAB_DOMAIN}:sub": "project_path:${GITLAB_PROJECT_PATH}:ref_type:branch:ref:*"
        }
      }
    }
  ]
}
EOF
)

# Check if role already exists
if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
    echo -e "${YELLOW}  Role already exists: ${ROLE_NAME}${NC}"
    echo -e "${BLUE}  Updating trust policy...${NC}"
    
    # Update trust policy
    echo "$TRUST_POLICY" > /tmp/trust-policy.json
    aws iam update-assume-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-document file:///tmp/trust-policy.json
    rm /tmp/trust-policy.json
    
    echo -e "${GREEN}  ✓ Trust policy updated${NC}"
else
    # Create the role
    echo "$TRUST_POLICY" > /tmp/trust-policy.json
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --description "Role for GitLab CI/CD to access AWS resources"
    rm /tmp/trust-policy.json
    
    echo -e "${GREEN}  ✓ IAM role created${NC}"
fi

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
echo ""

# Step 3: Attach ECR Permissions Policy
echo -e "${GREEN}Step 3: Attaching ECR Permissions Policy...${NC}"

# Create ECR permissions policy
ECR_POLICY_NAME="${ROLE_NAME}-ECR-Policy"
ECR_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories",
        "ecr:CreateRepository",
        "ecr:ListImages",
        "ecr:DescribeImages"
      ],
      "Resource": "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/agentic-platform-*"
    }
  ]
}
EOF
)

# Check if policy already exists
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ECR_POLICY_NAME}"
if aws iam get-policy --policy-arn "$POLICY_ARN" &> /dev/null; then
    echo -e "${YELLOW}  Policy already exists: ${ECR_POLICY_NAME}${NC}"
    
    # Create a new policy version
    echo "$ECR_POLICY" > /tmp/ecr-policy.json
    
    # Delete oldest version if we have 5 versions (AWS limit)
    VERSIONS=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
    VERSION_COUNT=$(echo "$VERSIONS" | wc -w)
    if [ "$VERSION_COUNT" -ge 5 ]; then
        OLDEST_VERSION=$(echo "$VERSIONS" | awk '{print $1}')
        aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$OLDEST_VERSION"
    fi
    
    aws iam create-policy-version \
        --policy-arn "$POLICY_ARN" \
        --policy-document file:///tmp/ecr-policy.json \
        --set-as-default
    rm /tmp/ecr-policy.json
    
    echo -e "${GREEN}  ✓ Policy updated${NC}"
else
    # Create the policy
    echo "$ECR_POLICY" > /tmp/ecr-policy.json
    aws iam create-policy \
        --policy-name "$ECR_POLICY_NAME" \
        --policy-document file:///tmp/ecr-policy.json \
        --description "ECR permissions for GitLab CI/CD"
    rm /tmp/ecr-policy.json
    
    echo -e "${GREEN}  ✓ Policy created${NC}"
fi

# Attach policy to role
if aws iam list-attached-role-policies --role-name "$ROLE_NAME" | grep -q "$ECR_POLICY_NAME"; then
    echo -e "${YELLOW}  Policy already attached to role${NC}"
else
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "$POLICY_ARN"
    
    echo -e "${GREEN}  ✓ Policy attached to role${NC}"
fi

echo ""

# Step 4: Output Configuration
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo -e "${BLUE}OIDC Provider ARN:${NC}"
echo "  ${OIDC_PROVIDER_ARN}"
echo ""
echo -e "${BLUE}IAM Role ARN:${NC}"
echo "  ${ROLE_ARN}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Add the following CI/CD variables to your GitLab project:"
echo ""
echo "   Variable Name: AWS_ROLE_ARN"
echo "   Value: ${ROLE_ARN}"
echo ""
echo "   Variable Name: AWS_REGION"
echo "   Value: ${AWS_REGION}"
echo ""
echo "2. In GitLab, go to: Settings > CI/CD > Variables"
echo "3. Add the variables above"
echo "4. Ensure variables are protected if using protected branches"
echo ""
echo -e "${BLUE}Trust Policy Summary:${NC}"
echo "  This role trusts GitLab project: ${GITLAB_PROJECT_PATH}"
echo "  For all branches (ref_type:branch:ref:*)"
echo ""
echo -e "${YELLOW}To modify trust policy for specific branches:${NC}"
echo "  Edit the trust policy condition to match your requirements"
echo "  Example for main branch only:"
echo "    \"${GITLAB_DOMAIN}:sub\": \"project_path:${GITLAB_PROJECT_PATH}:ref_type:branch:ref:main\""
echo ""
