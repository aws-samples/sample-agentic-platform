#!/bin/bash
#
# ATX Container Test Runner - GitLab CI/CD Setup Script (OIDC)
#
# This script automates the setup of AWS resources and IAM OIDC role
# for secure GitLab CI/CD deployment without long-lived credentials.
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "ATX Container Test Runner"
echo "GitLab CI/CD Setup (OIDC)"
echo "=========================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not found. Please install it first.${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: jq not found. Install for better output formatting.${NC}"
fi

# Get AWS account info
echo "Getting AWS account information..."
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="${AWS_REGION:-us-east-1}"

echo -e "${GREEN}AWS Account ID:${NC} ${AWS_ACCOUNT_ID}"
echo -e "${GREEN}AWS Region:${NC} ${AWS_REGION}"
echo ""

# Prompt for GitLab project info
echo -e "${BLUE}GitLab Project Information:${NC}"
read -p "Enter your GitLab project ID (found in Project Settings → General): " GITLAB_PROJECT_ID
if [[ -z "$GITLAB_PROJECT_ID" ]]; then
    echo -e "${RED}Error: GitLab project ID is required.${NC}"
    exit 1
fi

read -p "Enter GitLab instance URL [https://gitlab.com]: " GITLAB_URL
GITLAB_URL=${GITLAB_URL:-https://gitlab.com}

echo ""

# Prompt for bucket names
read -p "Enter source bucket name [atx-test-source-${AWS_ACCOUNT_ID}]: " SOURCE_BUCKET
SOURCE_BUCKET=${SOURCE_BUCKET:-atx-test-source-${AWS_ACCOUNT_ID}}

read -p "Enter results bucket name [atx-test-results-${AWS_ACCOUNT_ID}]: " RESULTS_BUCKET
RESULTS_BUCKET=${RESULTS_BUCKET:-atx-test-results-${AWS_ACCOUNT_ID}}

echo ""
echo "Configuration:"
echo "  GitLab Project ID: ${GITLAB_PROJECT_ID}"
echo "  GitLab URL: ${GITLAB_URL}"
echo "  Source Bucket: ${SOURCE_BUCKET}"
echo "  Results Bucket: ${RESULTS_BUCKET}"
echo ""

read -p "Continue with setup? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

# Create S3 buckets
echo ""
echo "Creating S3 buckets..."
aws s3 mb s3://${SOURCE_BUCKET} --region ${AWS_REGION} 2>/dev/null || echo "  Source bucket already exists"
aws s3 mb s3://${RESULTS_BUCKET} --region ${AWS_REGION} 2>/dev/null || echo "  Results bucket already exists"

# Enable versioning and encryption
echo "Configuring S3 buckets..."
aws s3api put-bucket-versioning --bucket ${SOURCE_BUCKET} --versioning-configuration Status=Enabled
aws s3api put-bucket-versioning --bucket ${RESULTS_BUCKET} --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket ${SOURCE_BUCKET} --server-side-encryption-configuration '{
  "Rules": [{
    "ApplyServerSideEncryptionByDefault": {
      "SSEAlgorithm": "AES256"
    }
  }]
}'

aws s3api put-bucket-encryption --bucket ${RESULTS_BUCKET} --server-side-encryption-configuration '{
  "Rules": [{
    "ApplyServerSideEncryptionByDefault": {
      "SSEAlgorithm": "AES256"
    }
  }]
}'

echo -e "${GREEN}✓ S3 buckets configured${NC}"

# Create OIDC Identity Provider
echo ""
echo "Creating OIDC Identity Provider..."

# Check if GitLab OIDC provider already exists
OIDC_ARN=""
GITLAB_DOMAIN_FOR_ARN=${GITLAB_URL#https://}
GITLAB_DOMAIN_FOR_ARN=${GITLAB_DOMAIN_FOR_ARN%%/*}
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${GITLAB_DOMAIN_FOR_ARN}" 2>/dev/null; then
    echo "  GitLab OIDC provider already exists"
    OIDC_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${GITLAB_DOMAIN_FOR_ARN}"
else
    # Get GitLab's OIDC thumbprint
    GITLAB_DOMAIN=${GITLAB_URL#https://}
    # Remove any path components to get just the domain
    GITLAB_DOMAIN=${GITLAB_DOMAIN%%/*}
    
    echo "  Getting SSL certificate for ${GITLAB_DOMAIN}..."
    THUMBPRINT=$(echo | openssl s_client -servername ${GITLAB_DOMAIN} -connect ${GITLAB_DOMAIN}:443 2>/dev/null | openssl x509 -fingerprint -sha1 -noout | cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')
    
    if [[ -z "$THUMBPRINT" ]]; then
        echo -e "${RED}Error: Could not get SSL certificate thumbprint for ${GITLAB_DOMAIN}${NC}"
        echo "Using GitLab.com default thumbprint..."
        THUMBPRINT="f879abce0008e4eb126e0097e46620f5aaae26ad"
    fi
    
    echo "  Using thumbprint: ${THUMBPRINT}"
    
    # Create OIDC provider
    OIDC_ARN=$(aws iam create-open-id-connect-provider \
        --url ${GITLAB_URL} \
        --thumbprint-list ${THUMBPRINT} \
        --client-id-list ${GITLAB_URL} \
        --query 'OpenIDConnectProviderArn' \
        --output text)
    
    echo "  ✓ OIDC provider created: ${OIDC_ARN}"
fi

# Create IAM role for GitLab CI
echo ""
echo "Creating IAM role for GitLab CI..."

ROLE_NAME="GitLabCIRole"
ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

# Create trust policy for OIDC
GITLAB_DOMAIN_FOR_POLICY=${GITLAB_URL#https://}
GITLAB_DOMAIN_FOR_POLICY=${GITLAB_DOMAIN_FOR_POLICY%%/*}

cat > /tmp/trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${GITLAB_DOMAIN_FOR_POLICY}:aud": "${GITLAB_URL}",
          "${GITLAB_DOMAIN_FOR_POLICY}:sub": "project_path:*:ref_type:branch:ref:main"
        },
        "StringLike": {
          "${GITLAB_DOMAIN_FOR_POLICY}:project_id": "${GITLAB_PROJECT_ID}"
        }
      }
    }
  ]
}
EOF

# Create or update IAM role
if aws iam get-role --role-name ${ROLE_NAME} >/dev/null 2>&1; then
    echo "  Updating existing IAM role..."
    aws iam update-assume-role-policy --role-name ${ROLE_NAME} --policy-document file:///tmp/trust-policy.json
else
    echo "  Creating new IAM role..."
    aws iam create-role --role-name ${ROLE_NAME} --assume-role-policy-document file:///tmp/trust-policy.json
fi

# Create permissions policy
cat > /tmp/permissions-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories",
        "ecr:CreateRepository",
        "ecr:DescribeImages",
        "ecr:ListImages"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECSAccess",
      "Effect": "Allow",
      "Action": [
        "ecs:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2Access",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeNetworkInterfaces",
        "ec2:CreateSecurityGroup",
        "ec2:CreateTags",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudFormationAccess",
      "Effect": "Allow",
      "Action": [
        "cloudformation:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMAccess",
      "Effect": "Allow",
      "Action": [
        "iam:GetRole",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:PassRole",
        "iam:CreateServiceLinkedRole"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LogsAccess",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3Access",
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "arn:aws:s3:::atx-test-*",
        "arn:aws:s3:::atx-test-*/*"
      ]
    }
  ]
}
EOF

# Attach permissions policy
aws iam put-role-policy \
    --role-name ${ROLE_NAME} \
    --policy-name GitLabCIPermissions \
    --policy-document file:///tmp/permissions-policy.json

echo -e "${GREEN}✓ IAM role configured${NC}"

# Display results
echo ""
echo "=========================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "=========================================="
echo ""
echo -e "${BLUE}Add these variables to GitLab CI/CD Settings:${NC}"
echo "(Settings → CI/CD → Variables)"
echo ""
echo "Variable Name              | Value                      | Protected | Masked"
echo "---------------------------|----------------------------|-----------|-------"
echo "AWS_REGION                 | ${AWS_REGION}              |           |"
echo "AWS_ACCOUNT_ID             | ${AWS_ACCOUNT_ID}          |           |"
echo "AWS_ROLE_ARN               | ${ROLE_ARN}                |           |"
echo "SOURCE_BUCKET              | ${SOURCE_BUCKET}           |           |"
echo "RESULTS_BUCKET             | ${RESULTS_BUCKET}          |           |"
echo ""
echo -e "${GREEN}✓ No access keys needed! OIDC provides secure, temporary credentials.${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Add the variables above to your GitLab project"
echo "2. Push this repository to GitLab:"
echo "   git remote add origin https://gitlab.com/your-username/atx-container-test-runner.git"
echo "   git push origin main"
echo "3. Watch the pipeline run in GitLab CI/CD → Pipelines"
echo ""
echo -e "${YELLOW}Benefits of OIDC:${NC}"
echo "• No long-lived access keys to manage"
echo "• Automatic credential rotation"
echo "• Enhanced security with temporary tokens"
echo "• Easier compliance and auditing"
echo ""

# Cleanup
rm -f /tmp/trust-policy.json /tmp/permissions-policy.json

echo -e "${GREEN}✓ Setup complete! Your GitLab CI/CD is now configured for secure OIDC authentication.${NC}"
