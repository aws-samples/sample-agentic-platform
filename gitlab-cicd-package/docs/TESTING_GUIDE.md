# GitLab CI/CD Pipeline Testing Guide

This guide provides comprehensive instructions for testing the GitLab CI/CD pipeline that builds and pushes container images to AWS ECR.

## Table of Contents

1. [AWS OIDC Setup for GitLab](#aws-oidc-setup-for-gitlab)
2. [GitLab Repository Setup](#gitlab-repository-setup)
3. [GitLab CI/CD Variable Configuration](#gitlab-cicd-variable-configuration)
4. [Test Scenarios](#test-scenarios)
5. [Validation Steps](#validation-steps)
6. [Troubleshooting Guide](#troubleshooting-guide)

---

## AWS OIDC Setup for GitLab

### Overview

OpenID Connect (OIDC) allows GitLab CI/CD to authenticate with AWS without storing long-lived credentials. This section guides you through setting up the AWS side of the OIDC integration.

### Prerequisites

- AWS account with administrative access
- AWS CLI installed and configured
- GitLab project path (format: `group/project` or `group/subgroup/project`)

### Step 1: Create OIDC Identity Provider in AWS

1. **Via AWS Console:**
   - Navigate to IAM → Identity providers → Add provider
   - Select "OpenID Connect"
   - Provider URL: `https://gitlab.com`
   - Audience: `https://gitlab.com`
   - Click "Add provider"

2. **Via AWS CLI:**
   ```bash
   aws iam create-open-id-connect-provider \
     --url https://gitlab.com \
     --client-id-list https://gitlab.com \
     --thumbprint-list 7e04de896a3e666283b9c0c5e9c6e5c6e5c6e5c6
   ```

   Note: The thumbprint value above is for GitLab.com. If using self-hosted GitLab, obtain the thumbprint using:
   ```bash
   echo | openssl s_client -servername gitlab.example.com -connect gitlab.example.com:443 2>/dev/null | openssl x509 -fingerprint -noout | sed 's/://g' | awk -F= '{print tolower($2)}'
   ```

### Step 2: Create IAM Role with Trust Policy

1. **Create Trust Policy JSON:**

   Create a file named `gitlab-trust-policy.json` with the following content:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/gitlab.com"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "gitlab.com:aud": "https://gitlab.com"
           },
           "StringLike": {
             "gitlab.com:sub": "project_path:YOUR_GROUP/YOUR_PROJECT:ref_type:branch:ref:*"
           }
         }
       }
     ]
   }
   ```

   **Important:** Replace the following placeholders:
   - `YOUR_ACCOUNT_ID`: Your AWS account ID (12-digit number)
   - `YOUR_GROUP/YOUR_PROJECT`: Your GitLab project path (e.g., `mycompany/agentic-platform`)

   **Trust Policy Variations:**

   - **Allow specific branch only:**
     ```json
     "gitlab.com:sub": "project_path:YOUR_GROUP/YOUR_PROJECT:ref_type:branch:ref:main"
     ```

   - **Allow all branches:**
     ```json
     "gitlab.com:sub": "project_path:YOUR_GROUP/YOUR_PROJECT:ref_type:branch:ref:*"
     ```

   - **Allow tags:**
     ```json
     "gitlab.com:sub": "project_path:YOUR_GROUP/YOUR_PROJECT:ref_type:tag:ref:*"
     ```

   - **Allow merge requests:**
     ```json
     "gitlab.com:sub": "project_path:YOUR_GROUP/YOUR_PROJECT:ref_type:merge_request:ref:*"
     ```

   - **Allow multiple conditions (recommended for testing):**
     ```json
     {
       "Version": "2012-10-17",
       "Statement": [
         {
           "Effect": "Allow",
           "Principal": {
             "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/gitlab.com"
           },
           "Action": "sts:AssumeRoleWithWebIdentity",
           "Condition": {
             "StringEquals": {
               "gitlab.com:aud": "https://gitlab.com"
             },
             "StringLike": {
               "gitlab.com:sub": [
                 "project_path:YOUR_GROUP/YOUR_PROJECT:ref_type:branch:ref:*",
                 "project_path:YOUR_GROUP/YOUR_PROJECT:ref_type:tag:ref:*",
                 "project_path:YOUR_GROUP/YOUR_PROJECT:ref_type:merge_request:ref:*"
               ]
             }
           }
         }
       ]
     }
     ```

2. **Create IAM Role:**

   ```bash
   aws iam create-role \
     --role-name GitLabCIECRRole \
     --assume-role-policy-document file://gitlab-trust-policy.json \
     --description "Role for GitLab CI/CD to push images to ECR"
   ```

3. **Note the Role ARN:**

   The command output will include the role ARN. Save this value - you'll need it for GitLab CI/CD variables.

   Example: `arn:aws:iam::123456789012:role/GitLabCIECRRole`

### Step 3: Attach ECR Permissions Policy

1. **Create ECR Permissions Policy JSON:**

   Create a file named `ecr-permissions-policy.json`:

   ```json
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
         "Resource": "arn:aws:ecr:*:YOUR_ACCOUNT_ID:repository/agentic-platform-*"
       }
     ]
   }
   ```

   **Important:** Replace `YOUR_ACCOUNT_ID` with your AWS account ID.

2. **Create and Attach Policy:**

   ```bash
   # Create the policy
   aws iam create-policy \
     --policy-name GitLabCIECRPolicy \
     --policy-document file://ecr-permissions-policy.json \
     --description "Permissions for GitLab CI/CD to manage ECR repositories"

   # Attach the policy to the role
   aws iam attach-role-policy \
     --role-name GitLabCIECRRole \
     --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/GitLabCIECRPolicy
   ```

   Replace `YOUR_ACCOUNT_ID` in the policy ARN.

### Step 4: Verify OIDC Configuration

1. **Check Identity Provider:**
   ```bash
   aws iam list-open-id-connect-providers
   ```

2. **Check Role Trust Policy:**
   ```bash
   aws iam get-role --role-name GitLabCIECRRole
   ```

3. **Check Attached Policies:**
   ```bash
   aws iam list-attached-role-policies --role-name GitLabCIECRRole
   ```

### Quick Setup Script

For convenience, here's a complete setup script:

```bash
#!/bin/bash

# Configuration
AWS_ACCOUNT_ID="123456789012"  # Replace with your account ID
GITLAB_PROJECT_PATH="mycompany/agentic-platform"  # Replace with your project path
ROLE_NAME="GitLabCIECRRole"
POLICY_NAME="GitLabCIECRPolicy"
AWS_REGION="us-east-1"  # Replace with your region

# Create OIDC provider (skip if already exists)
aws iam create-open-id-connect-provider \
  --url https://gitlab.com \
  --client-id-list https://gitlab.com \
  --thumbprint-list 7e04de896a3e666283b9c0c5e9c6e5c6e5c6e5c6 \
  2>/dev/null || echo "OIDC provider already exists"

# Create trust policy
cat > gitlab-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/gitlab.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "gitlab.com:aud": "https://gitlab.com"
        },
        "StringLike": {
          "gitlab.com:sub": [
            "project_path:${GITLAB_PROJECT_PATH}:ref_type:branch:ref:*",
            "project_path:${GITLAB_PROJECT_PATH}:ref_type:tag:ref:*",
            "project_path:${GITLAB_PROJECT_PATH}:ref_type:merge_request:ref:*"
          ]
        }
      }
    }
  ]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name ${ROLE_NAME} \
  --assume-role-policy-document file://gitlab-trust-policy.json \
  --description "Role for GitLab CI/CD to push images to ECR"

# Create ECR permissions policy
cat > ecr-permissions-policy.json <<EOF
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
      "Resource": "arn:aws:ecr:*:${AWS_ACCOUNT_ID}:repository/agentic-platform-*"
    }
  ]
}
EOF

# Create and attach policy
POLICY_ARN=$(aws iam create-policy \
  --policy-name ${POLICY_NAME} \
  --policy-document file://ecr-permissions-policy.json \
  --query 'Policy.Arn' \
  --output text)

aws iam attach-role-policy \
  --role-name ${ROLE_NAME} \
  --policy-arn ${POLICY_ARN}

# Get role ARN
ROLE_ARN=$(aws iam get-role --role-name ${ROLE_NAME} --query 'Role.Arn' --output text)

echo ""
echo "=========================================="
echo "AWS OIDC Setup Complete!"
echo "=========================================="
echo ""
echo "Add this to your GitLab CI/CD variables:"
echo "AWS_ROLE_ARN: ${ROLE_ARN}"
echo "AWS_REGION: ${AWS_REGION}"
echo ""
```

Save this as `setup-aws-oidc.sh`, update the configuration variables, and run:

```bash
chmod +x setup-aws-oidc.sh
./setup-aws-oidc.sh
```

---

## GitLab Repository Setup

### Overview

This section guides you through setting up a test GitLab repository to validate the CI/CD pipeline.

### Prerequisites

- GitLab account (GitLab.com or self-hosted instance)
- Git installed locally
- Access to create new repositories

### Step 1: Create Test Repository

1. **Via GitLab Web UI:**
   - Navigate to your GitLab group or personal namespace
   - Click "New project" → "Create blank project"
   - Project name: `agentic-platform-test` (or your preferred name)
   - Visibility: Private (recommended for testing)
   - Initialize with README: No (we'll add files manually)
   - Click "Create project"

2. **Note Your Project Path:**
   - Your project path will be in the format: `username/agentic-platform-test` or `group/agentic-platform-test`
   - You'll need this for AWS OIDC configuration

### Step 2: Clone Repository Locally

```bash
git clone git@gitlab.com:YOUR_USERNAME/agentic-platform-test.git
cd agentic-platform-test
```

Replace `YOUR_USERNAME` with your GitLab username or group name.

### Step 3: Create Required Directory Structure

The pipeline expects a specific directory structure:

```
agentic-platform-test/
├── .gitlab-ci.yml           # CI/CD pipeline configuration
├── deploy/
│   └── build-container.sh   # Build script
└── docker/                  # Service directories
    ├── service-1/
    │   └── Dockerfile
    ├── service-2/
    │   └── Dockerfile
    └── service-3/
        └── Dockerfile
```

Create the structure:

```bash
# Create directories
mkdir -p deploy
mkdir -p docker/service-1
mkdir -p docker/service-2
mkdir -p docker/service-3
```

### Step 4: Add Sample Dockerfiles

Create sample Dockerfiles for testing:

**docker/service-1/Dockerfile:**
```dockerfile
FROM alpine:3.18
RUN echo "Service 1" > /service.txt
CMD ["cat", "/service.txt"]
```

**docker/service-2/Dockerfile:**
```dockerfile
FROM alpine:3.18
RUN echo "Service 2" > /service.txt
CMD ["cat", "/service.txt"]
```

**docker/service-3/Dockerfile:**
```dockerfile
FROM alpine:3.18
RUN echo "Service 3" > /service.txt
CMD ["cat", "/service.txt"]
```

Create these files:

```bash
cat > docker/service-1/Dockerfile <<'EOF'
FROM alpine:3.18
RUN echo "Service 1" > /service.txt
CMD ["cat", "/service.txt"]
EOF

cat > docker/service-2/Dockerfile <<'EOF'
FROM alpine:3.18
RUN echo "Service 2" > /service.txt
CMD ["cat", "/service.txt"]
EOF

cat > docker/service-3/Dockerfile <<'EOF'
FROM alpine:3.18
RUN echo "Service 3" > /service.txt
CMD ["cat", "/service.txt"]
EOF
```

### Step 5: Add Build Script

Create the build script that the pipeline will execute:

**deploy/build-container.sh:**
```bash
#!/bin/bash
set -e

SERVICE_NAME=$1

if [ -z "$SERVICE_NAME" ]; then
  echo "Error: Service name not provided"
  exit 1
fi

echo "Building service: $SERVICE_NAME"

# Configuration
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPOSITORY_NAME="agentic-platform-${SERVICE_NAME}"
IMAGE_TAG="${CI_COMMIT_SHORT_SHA:-latest}"

echo "AWS Account: $AWS_ACCOUNT_ID"
echo "ECR Registry: $ECR_REGISTRY"
echo "Repository: $REPOSITORY_NAME"
echo "Image Tag: $IMAGE_TAG"

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}

# Check if repository exists, create if not
echo "Checking if ECR repository exists..."
if ! aws ecr describe-repositories --repository-names ${REPOSITORY_NAME} --region ${AWS_REGION} 2>/dev/null; then
  echo "Creating ECR repository: ${REPOSITORY_NAME}"
  aws ecr create-repository --repository-name ${REPOSITORY_NAME} --region ${AWS_REGION}
else
  echo "ECR repository already exists: ${REPOSITORY_NAME}"
fi

# Build image
echo "Building Docker image..."
docker build -t ${REPOSITORY_NAME}:${IMAGE_TAG} -f docker/${SERVICE_NAME}/Dockerfile docker/${SERVICE_NAME}/

# Tag image
echo "Tagging image..."
docker tag ${REPOSITORY_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${REPOSITORY_NAME}:${IMAGE_TAG}
docker tag ${REPOSITORY_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${REPOSITORY_NAME}:latest

# Push image
echo "Pushing image to ECR..."
docker push ${ECR_REGISTRY}/${REPOSITORY_NAME}:${IMAGE_TAG}
docker push ${ECR_REGISTRY}/${REPOSITORY_NAME}:latest

echo "Successfully built and pushed ${SERVICE_NAME}"
```

Create the file:

```bash
cat > deploy/build-container.sh <<'EOF'
#!/bin/bash
set -e

SERVICE_NAME=$1

if [ -z "$SERVICE_NAME" ]; then
  echo "Error: Service name not provided"
  exit 1
fi

echo "Building service: $SERVICE_NAME"

# Configuration
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPOSITORY_NAME="agentic-platform-${SERVICE_NAME}"
IMAGE_TAG="${CI_COMMIT_SHORT_SHA:-latest}"

echo "AWS Account: $AWS_ACCOUNT_ID"
echo "ECR Registry: $ECR_REGISTRY"
echo "Repository: $REPOSITORY_NAME"
echo "Image Tag: $IMAGE_TAG"

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}

# Check if repository exists, create if not
echo "Checking if ECR repository exists..."
if ! aws ecr describe-repositories --repository-names ${REPOSITORY_NAME} --region ${AWS_REGION} 2>/dev/null; then
  echo "Creating ECR repository: ${REPOSITORY_NAME}"
  aws ecr create-repository --repository-name ${REPOSITORY_NAME} --region ${AWS_REGION}
else
  echo "ECR repository already exists: ${REPOSITORY_NAME}"
fi

# Build image
echo "Building Docker image..."
docker build -t ${REPOSITORY_NAME}:${IMAGE_TAG} -f docker/${SERVICE_NAME}/Dockerfile docker/${SERVICE_NAME}/

# Tag image
echo "Tagging image..."
docker tag ${REPOSITORY_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${REPOSITORY_NAME}:${IMAGE_TAG}
docker tag ${REPOSITORY_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${REPOSITORY_NAME}:latest

# Push image
echo "Pushing image to ECR..."
docker push ${ECR_REGISTRY}/${REPOSITORY_NAME}:${IMAGE_TAG}
docker push ${ECR_REGISTRY}/${REPOSITORY_NAME}:latest

echo "Successfully built and pushed ${SERVICE_NAME}"
EOF

chmod +x deploy/build-container.sh
```

### Step 6: Add GitLab CI/CD Configuration

Copy the `.gitlab-ci.yml` file from your main repository or create it based on the pipeline design.

```bash
# If copying from existing repository
cp /path/to/main/repo/.gitlab-ci.yml .

# Or create manually - see the main repository for the complete configuration
```

### Step 7: Add Core Dependency Files (Optional)

For testing change detection with core dependencies, create sample files:

```bash
mkdir -p src/agentic_platform/core
echo "# Core module" > src/agentic_platform/core/__init__.py
```

### Step 8: Commit and Push Initial Setup

```bash
git add .
git commit -m "Initial setup: Add CI/CD pipeline and sample services"
git push origin main
```

### Repository Structure Requirements

The pipeline requires the following structure:

1. **docker/ directory:**
   - Must exist at repository root
   - Contains subdirectories for each service
   - Each service subdirectory must contain a `Dockerfile`

2. **deploy/build-container.sh:**
   - Must exist and be executable
   - Takes service name as first argument
   - Handles ECR login, build, tag, and push

3. **.gitlab-ci.yml:**
   - Must exist at repository root
   - Defines the three-stage pipeline

4. **Optional service-specific directories:**
   - `src/agentic_platform/service/{service}/`
   - `src/agentic_platform/agent/{service}/`
   - Changes in these trigger rebuilds for specific services

### Quick Setup Script

For convenience, here's a complete repository setup script:

```bash
#!/bin/bash

# Configuration
REPO_NAME="agentic-platform-test"
GITLAB_USERNAME="your-username"  # Replace with your GitLab username

# Create and navigate to repository
mkdir -p ${REPO_NAME}
cd ${REPO_NAME}

# Initialize git
git init
git remote add origin git@gitlab.com:${GITLAB_USERNAME}/${REPO_NAME}.git

# Create directory structure
mkdir -p deploy
mkdir -p docker/service-1
mkdir -p docker/service-2
mkdir -p docker/service-3
mkdir -p src/agentic_platform/core

# Create Dockerfiles
for i in 1 2 3; do
  cat > docker/service-${i}/Dockerfile <<EOF
FROM alpine:3.18
RUN echo "Service ${i}" > /service.txt
CMD ["cat", "/service.txt"]
EOF
done

# Create build script
cat > deploy/build-container.sh <<'EOF'
#!/bin/bash
set -e

SERVICE_NAME=$1

if [ -z "$SERVICE_NAME" ]; then
  echo "Error: Service name not provided"
  exit 1
fi

echo "Building service: $SERVICE_NAME"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPOSITORY_NAME="agentic-platform-${SERVICE_NAME}"
IMAGE_TAG="${CI_COMMIT_SHORT_SHA:-latest}"

echo "AWS Account: $AWS_ACCOUNT_ID"
echo "ECR Registry: $ECR_REGISTRY"
echo "Repository: $REPOSITORY_NAME"
echo "Image Tag: $IMAGE_TAG"

echo "Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}

echo "Checking if ECR repository exists..."
if ! aws ecr describe-repositories --repository-names ${REPOSITORY_NAME} --region ${AWS_REGION} 2>/dev/null; then
  echo "Creating ECR repository: ${REPOSITORY_NAME}"
  aws ecr create-repository --repository-name ${REPOSITORY_NAME} --region ${AWS_REGION}
else
  echo "ECR repository already exists: ${REPOSITORY_NAME}"
fi

echo "Building Docker image..."
docker build -t ${REPOSITORY_NAME}:${IMAGE_TAG} -f docker/${SERVICE_NAME}/Dockerfile docker/${SERVICE_NAME}/

echo "Tagging image..."
docker tag ${REPOSITORY_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${REPOSITORY_NAME}:${IMAGE_TAG}
docker tag ${REPOSITORY_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${REPOSITORY_NAME}:latest

echo "Pushing image to ECR..."
docker push ${ECR_REGISTRY}/${REPOSITORY_NAME}:${IMAGE_TAG}
docker push ${ECR_REGISTRY}/${REPOSITORY_NAME}:latest

echo "Successfully built and pushed ${SERVICE_NAME}"
EOF

chmod +x deploy/build-container.sh

# Create core module
echo "# Core module" > src/agentic_platform/core/__init__.py

# Create README
cat > README.md <<EOF
# Agentic Platform Test Repository

This is a test repository for validating the GitLab CI/CD pipeline.

## Services

- service-1
- service-2
- service-3

## Testing

See docs/TESTING_GUIDE.md for complete testing instructions.
EOF

# Note: You need to manually copy .gitlab-ci.yml from your main repository

echo ""
echo "=========================================="
echo "Repository Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Copy .gitlab-ci.yml from your main repository"
echo "2. Commit and push: git add . && git commit -m 'Initial setup' && git push origin main"
echo "3. Configure GitLab CI/CD variables (see next section)"
echo ""
```

Save as `setup-test-repo.sh` and run:

```bash
chmod +x setup-test-repo.sh
./setup-test-repo.sh
```

---

## GitLab CI/CD Variable Configuration

### Overview

GitLab CI/CD variables store configuration values that the pipeline needs to execute. This section covers all required and optional variables.

### Required Variables

#### AWS_ROLE_ARN

- **Description:** The ARN of the IAM role that GitLab will assume using OIDC
- **Type:** Variable
- **Protected:** Yes (recommended)
- **Masked:** No (ARNs are not sensitive)
- **Example Value:** `arn:aws:iam::123456789012:role/GitLabCIECRRole`
- **How to obtain:** Created in the AWS OIDC setup (see previous section)

#### AWS_REGION

- **Description:** The AWS region where ECR repositories are located
- **Type:** Variable
- **Protected:** No
- **Masked:** No
- **Example Value:** `us-east-1`
- **Default:** `us-east-1` (if not set, pipeline uses this default)
- **Common Values:**
  - `us-east-1` (US East - N. Virginia)
  - `us-west-2` (US West - Oregon)
  - `eu-west-1` (Europe - Ireland)
  - `ap-southeast-1` (Asia Pacific - Singapore)

### Optional Variables

#### MANUAL_SERVICES

- **Description:** Specifies which services to build when manually triggering the pipeline
- **Type:** Variable
- **Protected:** No
- **Masked:** No
- **When to use:** Only when manually triggering the pipeline
- **Valid Values:**
  - `all` - Build all discovered services
  - `changed` - Use change detection (default behavior)
  - Comma-separated list - Build specific services (e.g., `service-1,service-3`)
- **Example Values:**
  - `all`
  - `changed`
  - `service-1`
  - `service-1,service-2,service-3`
  - `memory-gateway,retrieval-gateway`

**Note:** This variable is typically set when manually triggering a pipeline, not as a persistent CI/CD variable.

### Setting Variables via GitLab Web UI

#### Method 1: Project-Level Variables (Recommended)

1. Navigate to your GitLab project
2. Go to **Settings** → **CI/CD**
3. Expand the **Variables** section
4. Click **Add variable**
5. Configure the variable:
   - **Key:** Enter variable name (e.g., `AWS_ROLE_ARN`)
   - **Value:** Enter variable value
   - **Type:** Select "Variable"
   - **Environment scope:** Select "All" (or specific environments)
   - **Protect variable:** Check for sensitive variables
   - **Mask variable:** Check for secrets (not needed for ARNs or regions)
   - **Expand variable reference:** Leave unchecked (default)
6. Click **Add variable**

**Screenshot Guide:**
```
Settings → CI/CD → Variables → Add variable

┌─────────────────────────────────────────┐
│ Key: AWS_ROLE_ARN                       │
│ Value: arn:aws:iam::123456789012:role/  │
│        GitLabCIECRRole                  │
│ Type: ○ Variable ○ File                 │
│ Environment scope: All (default)        │
│ Flags:                                  │
│   ☑ Protect variable                    │
│   ☐ Mask variable                       │
│   ☐ Expand variable reference           │
│                                         │
│ [Add variable]                          │
└─────────────────────────────────────────┘
```

#### Method 2: Group-Level Variables (For Multiple Projects)

If you have multiple projects that need the same variables:

1. Navigate to your GitLab group
2. Go to **Settings** → **CI/CD**
3. Expand the **Variables** section
4. Follow the same steps as project-level variables

Group-level variables are inherited by all projects in the group.

### Setting Variables via GitLab CLI

If you prefer command-line configuration:

```bash
# Install glab CLI (if not already installed)
# See: https://gitlab.com/gitlab-org/cli

# Set AWS_ROLE_ARN
glab variable set AWS_ROLE_ARN \
  --value "arn:aws:iam::123456789012:role/GitLabCIECRRole" \
  --scope "*" \
  --protected

# Set AWS_REGION
glab variable set AWS_REGION \
  --value "us-east-1" \
  --scope "*"
```

### Setting Variables via GitLab API

For automation or infrastructure-as-code:

```bash
# Configuration
GITLAB_TOKEN="your-personal-access-token"
PROJECT_ID="12345"  # Your project ID (found in project settings)
GITLAB_URL="https://gitlab.com"

# Set AWS_ROLE_ARN
curl --request POST "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/variables" \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  --form "key=AWS_ROLE_ARN" \
  --form "value=arn:aws:iam::123456789012:role/GitLabCIECRRole" \
  --form "protected=true"

# Set AWS_REGION
curl --request POST "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/variables" \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  --form "key=AWS_REGION" \
  --form "value=us-east-1"
```

### Variable Configuration Checklist

Use this checklist to ensure all variables are configured correctly:

- [ ] **AWS_ROLE_ARN** is set with the correct IAM role ARN
- [ ] **AWS_ROLE_ARN** is marked as protected
- [ ] **AWS_REGION** is set with the correct AWS region
- [ ] Variables are set at the appropriate scope (project or group)
- [ ] Variables are accessible in the environment scope where pipelines run
- [ ] Test pipeline can access variables (check job logs)

### Verifying Variable Configuration

After setting variables, verify they're accessible:

1. **Via GitLab UI:**
   - Go to **Settings** → **CI/CD** → **Variables**
   - Verify variables are listed
   - Check protection and masking settings

2. **Via Pipeline Job:**
   - Trigger a pipeline
   - Check the detect-changes job log
   - Look for lines like:
     ```
     AWS Region: us-east-1
     AWS Role ARN: arn:aws:iam::123456789012:role/GitLabCIECRRole
     ```

3. **Via Test Job:**
   - Add a temporary test job to `.gitlab-ci.yml`:
     ```yaml
     test-variables:
       stage: .pre
       script:
         - echo "AWS_REGION=${AWS_REGION}"
         - echo "AWS_ROLE_ARN=${AWS_ROLE_ARN}"
       rules:
         - when: manual
     ```
   - Run the job manually
   - Check the output

### Environment-Specific Variables

If you need different variables for different environments:

1. **Create environment-specific variables:**
   - Key: `AWS_ROLE_ARN`
   - Value: `arn:aws:iam::123456789012:role/GitLabCIDevRole`
   - Environment scope: `development`

   - Key: `AWS_ROLE_ARN`
   - Value: `arn:aws:iam::123456789012:role/GitLabCIProdRole`
   - Environment scope: `production`

2. **Update pipeline to use environments:**
   ```yaml
   build:
     stage: build
     environment:
       name: production
     # ... rest of job configuration
   ```

### Variable Precedence

GitLab resolves variables in this order (highest to lowest precedence):

1. Pipeline-specific variables (set when triggering manually)
2. Project-level variables
3. Group-level variables
4. Instance-level variables (GitLab admin only)
5. Pipeline configuration variables (defined in `.gitlab-ci.yml`)

### Security Best Practices

1. **Protect sensitive variables:**
   - Mark `AWS_ROLE_ARN` as protected
   - Protected variables are only available to protected branches/tags

2. **Use masked variables for secrets:**
   - Mask variables that contain sensitive data
   - Note: ARNs and regions are not secrets and don't need masking

3. **Limit variable scope:**
   - Use environment scopes to limit where variables are available
   - Use protected branches to limit who can access variables

4. **Rotate credentials regularly:**
   - Even with OIDC, review IAM role permissions periodically
   - Update trust policies if project paths change

5. **Audit variable access:**
   - Review audit logs for variable changes
   - Monitor who has access to project settings

### Troubleshooting Variable Issues

**Problem:** Pipeline fails with "AWS_ROLE_ARN not set"

**Solution:**
- Verify variable is set in Settings → CI/CD → Variables
- Check variable is not scoped to a specific environment
- Ensure variable name matches exactly (case-sensitive)

**Problem:** Pipeline fails with "Access Denied" when assuming role

**Solution:**
- Verify AWS_ROLE_ARN value is correct
- Check IAM role trust policy includes your GitLab project path
- Verify OIDC provider is configured in AWS

**Problem:** Variables not visible in job logs

**Solution:**
- Check if variables are masked (masked variables show as `[masked]`)
- Verify job has access to variables (check environment scope)
- Ensure variables are not protected if running on unprotected branch

### Complete Configuration Example

Here's a complete example of all variables configured:

```yaml
# Project: mycompany/agentic-platform-test
# Settings → CI/CD → Variables

Variables:
  - Key: AWS_ROLE_ARN
    Value: arn:aws:iam::123456789012:role/GitLabCIECRRole
    Type: Variable
    Protected: Yes
    Masked: No
    Environment scope: All (default)

  - Key: AWS_REGION
    Value: us-east-1
    Type: Variable
    Protected: No
    Masked: No
    Environment scope: All (default)
```

When manually triggering a pipeline, you can add:

```yaml
Manual Pipeline Variables:
  - Key: MANUAL_SERVICES
    Value: all
    # or: changed
    # or: service-1,service-2
```

---

## Test Scenarios

### Overview

This section provides detailed test scenarios to validate all pipeline functionality. Each scenario includes setup steps, expected behavior, and validation criteria.

### Prerequisites for All Scenarios

Before running any test scenario, ensure:

- [ ] AWS OIDC is configured (see AWS OIDC Setup section)
- [ ] GitLab repository is set up (see GitLab Repository Setup section)
- [ ] GitLab CI/CD variables are configured (see Variable Configuration section)
- [ ] Initial commit has been pushed to the repository

---

### Scenario 1: Push to Main Branch with Service Changes

**Objective:** Verify that pushing changes to a specific service triggers a build for only that service.

**Setup:**
1. Ensure you're on the main branch:
   ```bash
   git checkout main
   git pull origin main
   ```

2. Make a change to a specific service:
   ```bash
   echo "# Updated" >> docker/service-1/Dockerfile
   ```

3. Commit and push:
   ```bash
   git add docker/service-1/Dockerfile
   git commit -m "Update service-1 Dockerfile"
   git push origin main
   ```

**Expected Behavior:**
- Pipeline triggers automatically on push
- detect-changes job runs and identifies service-1 as changed
- build job creates a single parallel job for service-1
- service-1 container is built and pushed to ECR
- summary job reports that service-1 was built

**Validation:**
- Check pipeline status: Should be "passed"
- Check detect-changes job log: Should show "service-1" in build list
- Check build job: Should show only one parallel job (service-1)
- Check ECR: Repository `agentic-platform-service-1` should have new image with commit SHA tag
- Check summary job: Should list service-1 as built

**Variations:**
- Test with service-2: `echo "# Updated" >> docker/service-2/Dockerfile`
- Test with service-3: `echo "# Updated" >> docker/service-3/Dockerfile`
- Test with multiple services: Modify multiple Dockerfiles in one commit

---

### Scenario 2: Push to Main Branch with Core Changes

**Objective:** Verify that changes to core dependencies trigger builds for all services.

**Setup:**
1. Ensure you're on the main branch:
   ```bash
   git checkout main
   git pull origin main
   ```

2. Make a change to a core file:
   ```bash
   echo "# Core update" >> src/agentic_platform/core/__init__.py
   ```

3. Commit and push:
   ```bash
   git add src/agentic_platform/core/__init__.py
   git commit -m "Update core module"
   git push origin main
   ```

**Expected Behavior:**
- Pipeline triggers automatically on push
- detect-changes job identifies core file change
- detect-changes job marks ALL services for building
- build job creates parallel jobs for all services (service-1, service-2, service-3)
- All containers are built and pushed to ECR
- summary job reports all services were built

**Validation:**
- Check pipeline status: Should be "passed"
- Check detect-changes job log: Should show all services in build list with reason "core dependencies changed"
- Check build job: Should show three parallel jobs (one per service)
- Check ECR: All three repositories should have new images
- Check summary job: Should list all three services as built

**Core Files to Test:**
- `src/agentic_platform/core/**/*.py`
- `pyproject.toml`
- `requirements.txt`
- Any file matching the core patterns in the pipeline

---

### Scenario 3: Create Merge Request

**Objective:** Verify that creating a merge request triggers the pipeline for validation.

**Setup:**
1. Create a feature branch:
   ```bash
   git checkout -b feature/test-mr
   ```

2. Make a change:
   ```bash
   echo "# Feature update" >> docker/service-2/Dockerfile
   ```

3. Commit and push:
   ```bash
   git add docker/service-2/Dockerfile
   git commit -m "Feature: Update service-2"
   git push origin feature/test-mr
   ```

4. Create merge request via GitLab UI:
   - Navigate to your project
   - Click "Create merge request"
   - Source branch: `feature/test-mr`
   - Target branch: `main`
   - Click "Create merge request"

**Expected Behavior:**
- Pipeline triggers automatically on MR creation
- detect-changes job compares feature branch against main branch
- detect-changes job identifies service-2 as changed
- build job creates parallel job for service-2
- service-2 container is built and pushed to ECR
- summary job reports service-2 was built
- MR shows pipeline status

**Validation:**
- Check MR page: Pipeline should be running/passed
- Check detect-changes job log: Should show service-2 in build list
- Check build job: Should show one parallel job (service-2)
- Check ECR: Repository `agentic-platform-service-2` should have new image
- Check summary job: Should list service-2 as built

**Additional MR Tests:**
- Push additional commits to the MR branch
- Verify pipeline re-runs on each push
- Verify only changed services are built

---

### Scenario 4: Manual Trigger with "all"

**Objective:** Verify that manually triggering the pipeline with MANUAL_SERVICES="all" builds all services.

**Setup:**
1. Navigate to your GitLab project
2. Go to **CI/CD** → **Pipelines**
3. Click **Run pipeline**
4. Configure:
   - Branch: `main` (or any branch)
   - Variables:
     - Key: `MANUAL_SERVICES`
     - Value: `all`
5. Click **Run pipeline**

**Expected Behavior:**
- Pipeline starts immediately
- detect-changes job processes MANUAL_SERVICES="all"
- detect-changes job marks ALL services for building
- build job creates parallel jobs for all services
- All containers are built and pushed to ECR
- summary job reports all services were built

**Validation:**
- Check pipeline status: Should be "passed"
- Check detect-changes job log: Should show "Manual trigger: building all services"
- Check detect-changes job log: Should list all services in build list
- Check build job: Should show three parallel jobs
- Check ECR: All repositories should have new images
- Check summary job: Should list all services as built

---

### Scenario 5: Manual Trigger with Specific Services

**Objective:** Verify that manually triggering with a comma-separated list builds only specified services.

**Setup:**
1. Navigate to your GitLab project
2. Go to **CI/CD** → **Pipelines**
3. Click **Run pipeline**
4. Configure:
   - Branch: `main`
   - Variables:
     - Key: `MANUAL_SERVICES`
     - Value: `service-1,service-3`
5. Click **Run pipeline**

**Expected Behavior:**
- Pipeline starts immediately
- detect-changes job processes MANUAL_SERVICES="service-1,service-3"
- detect-changes job marks only service-1 and service-3 for building
- build job creates parallel jobs for service-1 and service-3 only
- Only specified containers are built and pushed to ECR
- summary job reports service-1 and service-3 were built

**Validation:**
- Check pipeline status: Should be "passed"
- Check detect-changes job log: Should show "Manual trigger: building specified services"
- Check detect-changes job log: Should list only service-1 and service-3
- Check build job: Should show two parallel jobs (service-1, service-3)
- Check ECR: Only service-1 and service-3 repositories should have new images
- Check summary job: Should list only service-1 and service-3 as built

**Variations:**
- Test with single service: `service-2`
- Test with all services: `service-1,service-2,service-3`
- Test with invalid service name: `service-1,invalid-service` (should skip invalid)

---

### Scenario 6: Push with No Changes

**Objective:** Verify that pushing commits without service changes skips the build stage.

**Setup:**
1. Ensure you're on the main branch:
   ```bash
   git checkout main
   git pull origin main
   ```

2. Make a change to a non-service file:
   ```bash
   echo "# Documentation update" >> README.md
   ```

3. Commit and push:
   ```bash
   git add README.md
   git commit -m "Update README"
   git push origin main
   ```

**Expected Behavior:**
- Pipeline triggers automatically on push
- detect-changes job runs and detects no service changes
- detect-changes job outputs empty build list
- build stage is skipped (no jobs created)
- summary job reports "No services were built"

**Validation:**
- Check pipeline status: Should be "passed"
- Check detect-changes job log: Should show "No services to build"
- Check build stage: Should be skipped or show no jobs
- Check summary job: Should display "No services were built (no changes detected)"
- Check ECR: No new images should be pushed

**Files to Test (should not trigger builds):**
- `README.md`
- `docs/**/*`
- `.gitignore`
- `LICENSE`
- Any file not matching service or core patterns

---

### Scenario 7: Cold Start (No ECR Repositories)

**Objective:** Verify that the pipeline creates ECR repositories and builds services when repositories don't exist.

**Setup:**
1. Delete ECR repositories (if they exist):
   ```bash
   aws ecr delete-repository --repository-name agentic-platform-service-1 --region us-east-1 --force
   aws ecr delete-repository --repository-name agentic-platform-service-2 --region us-east-1 --force
   aws ecr delete-repository --repository-name agentic-platform-service-3 --region us-east-1 --force
   ```

2. Trigger pipeline manually:
   - Navigate to **CI/CD** → **Pipelines**
   - Click **Run pipeline**
   - Branch: `main`
   - Variables: `MANUAL_SERVICES` = `changed` (or leave empty)
   - Click **Run pipeline**

**Expected Behavior:**
- Pipeline starts
- detect-changes job queries ECR for repositories
- detect-changes job finds all repositories are missing
- detect-changes job marks ALL services for building (due to missing repos)
- build job creates parallel jobs for all services
- Build script creates ECR repositories during build process
- All containers are built and pushed to newly created ECR repositories
- summary job reports all services were built

**Validation:**
- Check pipeline status: Should be "passed"
- Check detect-changes job log: Should show "ECR repository does not exist" for each service
- Check detect-changes job log: Should list all services with reason "missing ECR repository"
- Check build job: Should show three parallel jobs
- Check build job logs: Should show "Creating ECR repository" messages
- Check ECR: All three repositories should exist with new images
- Check summary job: Should list all services as built

**Note:** This scenario is important for initial deployment or disaster recovery.

---

### Scenario 8: Push to Develop Branch

**Objective:** Verify that pushing to the develop branch triggers the pipeline.

**Setup:**
1. Create or checkout develop branch:
   ```bash
   git checkout -b develop
   # or if it exists: git checkout develop
   ```

2. Make a change:
   ```bash
   echo "# Develop update" >> docker/service-1/Dockerfile
   ```

3. Commit and push:
   ```bash
   git add docker/service-1/Dockerfile
   git commit -m "Update service-1 on develop"
   git push origin develop
   ```

**Expected Behavior:**
- Pipeline triggers automatically on push to develop
- Same behavior as pushing to main
- service-1 is built and pushed to ECR

**Validation:**
- Check pipeline status: Should be "passed"
- Check detect-changes job: Should identify service-1
- Check build job: Should build service-1
- Check ECR: Should have new image tagged with commit SHA

---

### Scenario 9: Version Tag Push

**Objective:** Verify that pushing a version tag triggers the pipeline.

**Setup:**
1. Ensure you're on main branch:
   ```bash
   git checkout main
   git pull origin main
   ```

2. Create and push a version tag:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

**Expected Behavior:**
- Pipeline triggers automatically on tag push
- detect-changes job runs change detection
- Services with changes are built
- Images are tagged with version tag

**Validation:**
- Check pipeline status: Should be "passed"
- Check pipeline was triggered by tag
- Check ECR: Images should be tagged with v1.0.0

---

### Scenario 10: Service-Specific Directory Changes

**Objective:** Verify that changes in service-specific source directories trigger builds.

**Setup:**
1. Create service-specific directory:
   ```bash
   mkdir -p src/agentic_platform/service/service-1
   echo "# Service 1 code" > src/agentic_platform/service/service-1/__init__.py
   ```

2. Commit and push:
   ```bash
   git add src/agentic_platform/service/service-1/
   git commit -m "Add service-1 source code"
   git push origin main
   ```

**Expected Behavior:**
- Pipeline triggers automatically
- detect-changes job identifies service-1 directory change
- Only service-1 is built

**Validation:**
- Check detect-changes job log: Should show service-1 with reason "service-specific changes"
- Check build job: Should build only service-1

**Variations:**
- Test with `src/agentic_platform/agent/service-1/`
- Test with hyphen/underscore variations (service-1 vs service_1)

---

### Scenario 11: Parallel Build Failure Handling

**Objective:** Verify that failure of one service build doesn't prevent other services from building.

**Setup:**
1. Intentionally break one service's Dockerfile:
   ```bash
   echo "INVALID DOCKERFILE SYNTAX" > docker/service-2/Dockerfile
   ```

2. Make valid changes to other services:
   ```bash
   echo "# Update" >> docker/service-1/Dockerfile
   echo "# Update" >> docker/service-3/Dockerfile
   ```

3. Commit and push:
   ```bash
   git add docker/
   git commit -m "Update all services (service-2 broken)"
   git push origin main
   ```

**Expected Behavior:**
- Pipeline triggers automatically
- detect-changes job marks all three services for building
- build job creates three parallel jobs
- service-1 build succeeds
- service-2 build fails (invalid Dockerfile)
- service-3 build succeeds (continues despite service-2 failure)
- Pipeline overall status is "failed" (due to service-2)
- summary job still runs and reports results

**Validation:**
- Check pipeline status: Should be "failed"
- Check build jobs:
  - service-1: Should be "passed"
  - service-2: Should be "failed"
  - service-3: Should be "passed"
- Check ECR:
  - service-1: Should have new image
  - service-2: Should not have new image
  - service-3: Should have new image
- Check summary job: Should run and list all services attempted

**Cleanup:**
```bash
# Fix the broken Dockerfile
cat > docker/service-2/Dockerfile <<'EOF'
FROM alpine:3.18
RUN echo "Service 2" > /service.txt
CMD ["cat", "/service.txt"]
EOF

git add docker/service-2/Dockerfile
git commit -m "Fix service-2 Dockerfile"
git push origin main
```

---

### Test Scenario Summary Table

| Scenario | Trigger | Expected Services Built | Key Validation |
|----------|---------|------------------------|----------------|
| 1. Service change | Push to main | service-1 only | Check build list |
| 2. Core change | Push to main | All services | Check "core dependencies" reason |
| 3. Merge request | Create MR | Changed services | Check MR pipeline |
| 4. Manual "all" | Manual trigger | All services | Check manual trigger log |
| 5. Manual specific | Manual trigger | Specified services only | Check service list |
| 6. No changes | Push to main | None (skip build) | Check "no changes" message |
| 7. Cold start | Manual trigger | All services | Check "missing ECR" reason |
| 8. Develop branch | Push to develop | Changed services | Check branch trigger |
| 9. Version tag | Push tag | Changed services | Check tag trigger |
| 10. Service dir | Push to main | Specific service | Check service-specific reason |
| 11. Build failure | Push to main | Partial (some fail) | Check parallel independence |

---

### Running All Test Scenarios

For comprehensive testing, run all scenarios in order:

```bash
#!/bin/bash
# test-all-scenarios.sh

echo "Running all test scenarios..."

# Scenario 1: Service change
echo "=== Scenario 1: Service change ==="
git checkout main
echo "# Test 1" >> docker/service-1/Dockerfile
git add docker/service-1/Dockerfile
git commit -m "Test: Scenario 1 - Service change"
git push origin main
echo "Check pipeline, then press Enter to continue..."
read

# Scenario 2: Core change
echo "=== Scenario 2: Core change ==="
echo "# Test 2" >> src/agentic_platform/core/__init__.py
git add src/agentic_platform/core/__init__.py
git commit -m "Test: Scenario 2 - Core change"
git push origin main
echo "Check pipeline, then press Enter to continue..."
read

# Scenario 6: No changes
echo "=== Scenario 6: No changes ==="
echo "# Test 6" >> README.md
git add README.md
git commit -m "Test: Scenario 6 - No changes"
git push origin main
echo "Check pipeline, then press Enter to continue..."
read

# Add more scenarios as needed...

echo "All scenarios complete!"
```

---

## Validation Steps

### Overview

This section provides detailed steps to validate that the pipeline is working correctly. Use these validation steps after running any test scenario.

---

### 1. Check Pipeline Execution

#### Via GitLab Web UI

1. **Navigate to Pipelines:**
   - Go to your GitLab project
   - Click **CI/CD** → **Pipelines**
   - You should see a list of pipeline runs

2. **Check Pipeline Status:**
   - Look for the most recent pipeline
   - Status indicators:
     - 🔵 **Running** - Pipeline is currently executing
     - ✅ **Passed** - All jobs completed successfully
     - ❌ **Failed** - One or more jobs failed
     - ⚠️ **Warning** - Jobs passed with warnings
     - ⏸️ **Canceled** - Pipeline was manually canceled
     - ⏭️ **Skipped** - Pipeline was skipped

3. **View Pipeline Details:**
   - Click on the pipeline to see detailed view
   - You should see three stages:
     - `detect-changes`
     - `build`
     - `summary`

4. **Check Stage Status:**
   - Each stage should show its status
   - Click on a stage to see jobs within it

#### Via GitLab CLI

```bash
# List recent pipelines
glab ci list

# View specific pipeline
glab ci view <pipeline-id>

# Check pipeline status
glab ci status
```

#### Via GitLab API

```bash
# Configuration
GITLAB_TOKEN="your-token"
PROJECT_ID="12345"
GITLAB_URL="https://gitlab.com"

# Get latest pipeline
curl --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/pipelines?per_page=1"

# Get pipeline details
curl --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/pipelines/<pipeline-id>"
```

**Expected Results:**
- Pipeline should appear in the list
- Pipeline should have a status (running, passed, or failed)
- All three stages should be visible

---

### 2. Verify Service Detection

#### Check detect-changes Job Log

1. **Open Job Log:**
   - Navigate to pipeline details
   - Click on the `detect-changes` job
   - View the job log

2. **Look for Service Discovery:**
   ```
   Discovering services from docker/ directory...
   Found services: service-1 service-2 service-3
   ```

3. **Look for Change Detection:**
   ```
   Detecting changes...
   Changed files:
   docker/service-1/Dockerfile
   
   Services to build due to changes:
   - service-1 (reason: service-specific changes)
   ```

4. **Look for ECR Repository Check:**
   ```
   Checking ECR repositories...
   Checking repository: agentic-platform-service-1 - EXISTS
   Checking repository: agentic-platform-service-2 - EXISTS
   Checking repository: agentic-platform-service-3 - EXISTS
   ```

5. **Look for Final Build List:**
   ```
   Final build list:
   ["service-1"]
   
   Services to build: 1
   ```

6. **Check Artifact:**
   - Scroll to the bottom of the job log
   - Look for "Uploading artifacts" section
   - Should show `build.env` artifact uploaded

#### Verify Build List Content

1. **Download Artifact:**
   - In the job view, click **Browse** next to artifacts
   - Download `build.env` file
   - Open in text editor

2. **Check Content:**
   ```
   SERVICES_TO_BUILD=["service-1"]
   BUILD_COUNT=1
   ```

#### Via GitLab CLI

```bash
# View job log
glab ci view --job detect-changes

# Download artifacts
glab ci artifact detect-changes
```

**Expected Results:**
- Service discovery should find all services with Dockerfiles
- Change detection should identify correct services
- ECR check should show repository status
- Build list should contain only services that need building
- Artifact should be uploaded successfully

---

### 3. Verify Parallel Jobs

#### Check Build Stage Jobs

1. **View Build Stage:**
   - Navigate to pipeline details
   - Look at the `build` stage
   - You should see parallel jobs

2. **Count Parallel Jobs:**
   - Number of jobs should match BUILD_COUNT from detect-changes
   - Each job should be named with the service name
   - Example: `build: [service-1]`, `build: [service-2]`

3. **Check Job Status:**
   - Each job should show individual status
   - Jobs should run in parallel (check timestamps)
   - Failed jobs should not prevent other jobs from running

4. **View Individual Job Logs:**
   - Click on a specific build job
   - Check the log for build progress

#### Verify Parallel Execution

1. **Check Job Start Times:**
   - Click on each build job
   - Note the start time
   - Jobs should start within seconds of each other (parallel execution)

2. **Check Job Duration:**
   - Jobs should run independently
   - One slow job shouldn't delay others

#### Example Build Job Log

```
Building service: service-1
AWS Account: 123456789012
ECR Registry: 123456789012.dkr.ecr.us-east-1.amazonaws.com
Repository: agentic-platform-service-1
Image Tag: abc123de

Logging in to ECR...
Login Succeeded

Checking if ECR repository exists...
ECR repository already exists: agentic-platform-service-1

Building Docker image...
[+] Building 5.2s (7/7) FINISHED
...

Tagging image...

Pushing image to ECR...
The push refers to repository [123456789012.dkr.ecr.us-east-1.amazonaws.com/agentic-platform-service-1]
abc123de: digest: sha256:... size: 1234

Successfully built and pushed service-1
```

**Expected Results:**
- Number of parallel jobs matches services to build
- Jobs run simultaneously (parallel execution)
- Each job shows complete build process
- Jobs are independent (failures don't cascade)

---

### 4. Verify ECR Images

#### Via AWS Console

1. **Navigate to ECR:**
   - Open AWS Console
   - Go to **ECR** (Elastic Container Registry)
   - Select your region (e.g., us-east-1)

2. **Check Repositories:**
   - You should see repositories named `agentic-platform-{service}`
   - Example: `agentic-platform-service-1`

3. **View Repository Images:**
   - Click on a repository
   - You should see images with tags:
     - Commit SHA tag (e.g., `abc123de`)
     - `latest` tag

4. **Check Image Details:**
   - Click on an image
   - Check:
     - Image size
     - Push date/time
     - Image digest
     - Tags

#### Via AWS CLI

```bash
# List ECR repositories
aws ecr describe-repositories \
  --region us-east-1 \
  --query 'repositories[?starts_with(repositoryName, `agentic-platform-`)].repositoryName' \
  --output table

# List images in a repository
aws ecr list-images \
  --repository-name agentic-platform-service-1 \
  --region us-east-1 \
  --output table

# Get image details
aws ecr describe-images \
  --repository-name agentic-platform-service-1 \
  --region us-east-1 \
  --output json

# Check latest image
aws ecr describe-images \
  --repository-name agentic-platform-service-1 \
  --region us-east-1 \
  --image-ids imageTag=latest \
  --query 'imageDetails[0].[imagePushedAt,imageSizeInBytes,imageDigest]' \
  --output table
```

#### Verify Image Tags

```bash
# Get all tags for a repository
aws ecr list-images \
  --repository-name agentic-platform-service-1 \
  --region us-east-1 \
  --query 'imageIds[*].imageTag' \
  --output table
```

Expected tags:
- Commit SHA (e.g., `abc123de`)
- `latest`

#### Pull and Test Image (Optional)

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.us-east-1.amazonaws.com

# Pull image
docker pull 123456789012.dkr.ecr.us-east-1.amazonaws.com/agentic-platform-service-1:latest

# Run image
docker run --rm 123456789012.dkr.ecr.us-east-1.amazonaws.com/agentic-platform-service-1:latest

# Expected output: Service 1
```

#### Validation Script

```bash
#!/bin/bash
# validate-ecr-images.sh

AWS_REGION="us-east-1"
SERVICES=("service-1" "service-2" "service-3")

echo "Validating ECR images..."
echo ""

for service in "${SERVICES[@]}"; do
  REPO_NAME="agentic-platform-${service}"
  
  echo "Checking ${REPO_NAME}..."
  
  # Check if repository exists
  if aws ecr describe-repositories \
    --repository-names ${REPO_NAME} \
    --region ${AWS_REGION} &>/dev/null; then
    echo "  ✓ Repository exists"
    
    # Check for images
    IMAGE_COUNT=$(aws ecr list-images \
      --repository-name ${REPO_NAME} \
      --region ${AWS_REGION} \
      --query 'length(imageIds)' \
      --output text)
    
    echo "  ✓ Images found: ${IMAGE_COUNT}"
    
    # Check for latest tag
    if aws ecr describe-images \
      --repository-name ${REPO_NAME} \
      --region ${AWS_REGION} \
      --image-ids imageTag=latest &>/dev/null; then
      echo "  ✓ Latest tag exists"
    else
      echo "  ✗ Latest tag missing"
    fi
  else
    echo "  ✗ Repository does not exist"
  fi
  
  echo ""
done

echo "Validation complete!"
```

**Expected Results:**
- ECR repositories exist for built services
- Images have correct tags (commit SHA and latest)
- Images were pushed recently (check timestamp)
- Image size is reasonable (not empty)

---

### 5. Verify Summary Output

#### Check Summary Job Log

1. **Open Summary Job:**
   - Navigate to pipeline details
   - Click on the `summary` job
   - View the job log

2. **Check Summary Content:**

   **When services were built:**
   ```
   ========================================
   Build Summary
   ========================================
   
   The following services were built and pushed to ECR:
   - service-1
   
   Total services built: 1
   ```

   **When no services were built:**
   ```
   ========================================
   Build Summary
   ========================================
   
   No services were built (no changes detected)
   ```

3. **Verify Summary Accuracy:**
   - Compare summary with detect-changes build list
   - Ensure all services in build list are mentioned
   - Check total count matches

#### Summary Job Always Runs

The summary job should run even if build jobs fail:

1. **Check Job Rules:**
   - Summary job should have `when: always`
   - Should run regardless of previous job status

2. **Verify in Failed Pipelines:**
   - Trigger a pipeline with a failing build
   - Summary job should still execute
   - Summary should report the attempt

**Expected Results:**
- Summary job always runs (even on failures)
- Summary accurately lists built services
- Summary shows correct count
- Summary message is clear and informative

---

### Complete Validation Checklist

Use this checklist after running any test scenario:

#### Pipeline Execution
- [ ] Pipeline triggered successfully
- [ ] Pipeline shows correct trigger type (push, MR, manual)
- [ ] All three stages are present (detect-changes, build, summary)
- [ ] Pipeline completes (passes or fails as expected)

#### Service Detection
- [ ] detect-changes job completes successfully
- [ ] Service discovery finds all services
- [ ] Change detection identifies correct services
- [ ] ECR repository check runs
- [ ] Build list is generated correctly
- [ ] Artifact (build.env) is uploaded

#### Parallel Jobs
- [ ] Correct number of build jobs created
- [ ] Jobs run in parallel (check timestamps)
- [ ] Each job processes one service
- [ ] Job failures don't prevent other jobs from running
- [ ] All build jobs complete (pass or fail)

#### ECR Images
- [ ] ECR repositories exist for built services
- [ ] Images have commit SHA tags
- [ ] Images have latest tags
- [ ] Images were pushed recently
- [ ] Image sizes are reasonable

#### Summary Output
- [ ] Summary job runs (even if builds fail)
- [ ] Summary lists correct services
- [ ] Summary shows correct count
- [ ] Summary message matches pipeline results

#### AWS Authentication
- [ ] OIDC authentication succeeds
- [ ] AWS credentials are obtained
- [ ] ECR login succeeds
- [ ] No authentication errors in logs

---

### Automated Validation Script

For comprehensive validation, use this script:

```bash
#!/bin/bash
# validate-pipeline.sh

set -e

# Configuration
GITLAB_TOKEN="your-token"
PROJECT_ID="12345"
GITLAB_URL="https://gitlab.com"
AWS_REGION="us-east-1"

echo "=========================================="
echo "Pipeline Validation Script"
echo "=========================================="
echo ""

# Get latest pipeline
echo "1. Checking latest pipeline..."
PIPELINE_ID=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/pipelines?per_page=1" | \
  jq -r '.[0].id')

PIPELINE_STATUS=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/pipelines/${PIPELINE_ID}" | \
  jq -r '.status')

echo "   Pipeline ID: ${PIPELINE_ID}"
echo "   Status: ${PIPELINE_STATUS}"
echo ""

# Check jobs
echo "2. Checking pipeline jobs..."
JOBS=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/pipelines/${PIPELINE_ID}/jobs")

DETECT_STATUS=$(echo ${JOBS} | jq -r '.[] | select(.name=="detect-changes") | .status')
BUILD_COUNT=$(echo ${JOBS} | jq '[.[] | select(.stage=="build")] | length')
SUMMARY_STATUS=$(echo ${JOBS} | jq -r '.[] | select(.name=="summary") | .status')

echo "   detect-changes: ${DETECT_STATUS}"
echo "   build jobs: ${BUILD_COUNT}"
echo "   summary: ${SUMMARY_STATUS}"
echo ""

# Check ECR repositories
echo "3. Checking ECR repositories..."
REPOS=$(aws ecr describe-repositories \
  --region ${AWS_REGION} \
  --query 'repositories[?starts_with(repositoryName, `agentic-platform-`)].repositoryName' \
  --output text)

echo "   Found repositories:"
for repo in ${REPOS}; do
  IMAGE_COUNT=$(aws ecr list-images \
    --repository-name ${repo} \
    --region ${AWS_REGION} \
    --query 'length(imageIds)' \
    --output text)
  echo "     - ${repo} (${IMAGE_COUNT} images)"
done
echo ""

# Summary
echo "=========================================="
echo "Validation Complete!"
echo "=========================================="
echo ""

if [ "${PIPELINE_STATUS}" == "success" ]; then
  echo "✓ Pipeline passed successfully"
  exit 0
else
  echo "✗ Pipeline status: ${PIPELINE_STATUS}"
  exit 1
fi
```

Save as `validate-pipeline.sh`, configure variables, and run:

```bash
chmod +x validate-pipeline.sh
./validate-pipeline.sh
```

---

## Troubleshooting Guide

### Overview

This section provides solutions to common issues you may encounter when testing the GitLab CI/CD pipeline.

---

### OIDC Authentication Errors

#### Error: "An error occurred (InvalidIdentityToken) when calling the AssumeRoleWithWebIdentity operation"

**Symptoms:**
- detect-changes job fails during AWS authentication
- Error message mentions "InvalidIdentityToken"

**Possible Causes:**
1. OIDC provider not configured in AWS
2. Incorrect provider URL or audience
3. GitLab JWT token format changed

**Solutions:**

1. **Verify OIDC Provider Exists:**
   ```bash
   aws iam list-open-id-connect-providers
   ```
   
   Should show: `arn:aws:iam::ACCOUNT_ID:oidc-provider/gitlab.com`

2. **Check Provider Configuration:**
   ```bash
   aws iam get-open-id-connect-provider \
     --open-id-connect-provider-arn arn:aws:iam::ACCOUNT_ID:oidc-provider/gitlab.com
   ```
   
   Verify:
   - URL: `https://gitlab.com`
   - ClientIDList includes: `https://gitlab.com`

3. **Recreate OIDC Provider:**
   ```bash
   # Delete existing provider
   aws iam delete-open-id-connect-provider \
     --open-id-connect-provider-arn arn:aws:iam::ACCOUNT_ID:oidc-provider/gitlab.com
   
   # Create new provider
   aws iam create-open-id-connect-provider \
     --url https://gitlab.com \
     --client-id-list https://gitlab.com \
     --thumbprint-list 7e04de896a3e666283b9c0c5e9c6e5c6e5c6e5c6
   ```

---

#### Error: "An error occurred (AccessDenied) when calling the AssumeRoleWithWebIdentity operation"

**Symptoms:**
- detect-changes job fails during AWS authentication
- Error message mentions "AccessDenied" or "not authorized to perform: sts:AssumeRoleWithWebIdentity"

**Possible Causes:**
1. IAM role trust policy doesn't match GitLab project path
2. Trust policy condition is too restrictive
3. Role ARN is incorrect

**Solutions:**

1. **Verify Role ARN:**
   - Check GitLab CI/CD variable `AWS_ROLE_ARN`
   - Ensure it matches the actual role ARN in AWS
   ```bash
   aws iam get-role --role-name GitLabCIECRRole --query 'Role.Arn'
   ```

2. **Check Trust Policy:**
   ```bash
   aws iam get-role --role-name GitLabCIECRRole --query 'Role.AssumeRolePolicyDocument'
   ```
   
   Verify the trust policy includes:
   - Correct Federated principal (OIDC provider ARN)
   - Correct gitlab.com:sub condition with your project path
   - Correct gitlab.com:aud condition

3. **Update Trust Policy:**
   
   Create `updated-trust-policy.json`:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/gitlab.com"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "gitlab.com:aud": "https://gitlab.com"
           },
           "StringLike": {
             "gitlab.com:sub": [
               "project_path:YOUR_GROUP/YOUR_PROJECT:ref_type:branch:ref:*",
               "project_path:YOUR_GROUP/YOUR_PROJECT:ref_type:tag:ref:*",
               "project_path:YOUR_GROUP/YOUR_PROJECT:ref_type:merge_request:ref:*"
             ]
           }
         }
       }
     ]
   }
   ```
   
   Update the role:
   ```bash
   aws iam update-assume-role-policy \
     --role-name GitLabCIECRRole \
     --policy-document file://updated-trust-policy.json
   ```

4. **Verify Project Path:**
   - In GitLab, go to Settings → General
   - Check "Project name" and "Project slug"
   - Your project path is: `group/project-slug`
   - Ensure this matches the trust policy

---

#### Error: "Could not retrieve JWT token"

**Symptoms:**
- detect-changes job fails before AWS authentication
- Error mentions CI_JOB_JWT_V2 or JWT token

**Possible Causes:**
1. GitLab instance doesn't support JWT tokens
2. JWT token generation is disabled
3. Using self-hosted GitLab with incorrect configuration

**Solutions:**

1. **Check GitLab Version:**
   - JWT tokens (CI_JOB_JWT_V2) require GitLab 14.7+
   - Upgrade GitLab if necessary

2. **For Self-Hosted GitLab:**
   - Ensure JWT signing is configured
   - Check GitLab admin settings for OIDC configuration

3. **Verify Token in Job:**
   Add debug step to pipeline:
   ```yaml
   debug-jwt:
     stage: .pre
     script:
       - echo "JWT token length: ${#CI_JOB_JWT_V2}"
       - echo "JWT exists: $([ -n "$CI_JOB_JWT_V2" ] && echo 'yes' || echo 'no')"
     rules:
       - when: manual
   ```

---

### Git History Issues

#### Error: "fatal: bad revision 'HEAD~1'"

**Symptoms:**
- detect-changes job fails during git diff
- Error mentions "bad revision" or "unknown revision"

**Possible Causes:**
1. Shallow clone (limited git history)
2. First commit in repository
3. New branch with no parent

**Solutions:**

1. **Increase Git Depth:**
   
   Add to `.gitlab-ci.yml`:
   ```yaml
   variables:
     GIT_DEPTH: 50  # Fetch more history
   ```

2. **Handle First Commit:**
   
   The pipeline already handles this by checking if `CI_COMMIT_BEFORE_SHA` is all zeros:
   ```bash
   if [ "$CI_COMMIT_BEFORE_SHA" == "0000000000000000000000000000000000000000" ]; then
     # First commit - build all services
   fi
   ```

3. **Disable Shallow Clone (Not Recommended):**
   ```yaml
   variables:
     GIT_DEPTH: 0  # Full clone (slower)
   ```

---

#### Error: "No changes detected" when changes exist

**Symptoms:**
- Made changes to service files
- Pipeline runs but reports no changes
- No services are built

**Possible Causes:**
1. Changes are in files not monitored by change detection
2. Git diff is comparing wrong commits
3. File paths don't match expected patterns

**Solutions:**

1. **Check File Paths:**
   
   Verify your changes are in monitored directories:
   - `docker/{service}/`
   - `src/agentic_platform/service/{service}/`
   - `src/agentic_platform/agent/{service}/`
   - Core files (see pipeline configuration)

2. **Debug Change Detection:**
   
   Add debug output to detect-changes job:
   ```bash
   # In .gitlab-ci.yml detect-changes script
   echo "Comparing commits: $BEFORE_SHA to $AFTER_SHA"
   git diff --name-only $BEFORE_SHA $AFTER_SHA
   ```

3. **Manual Trigger Workaround:**
   
   If change detection is failing, manually trigger with specific services:
   - Go to CI/CD → Pipelines → Run pipeline
   - Set MANUAL_SERVICES to the services you want to build

4. **Check Service Name Matching:**
   
   Ensure service directory names match exactly:
   - Directory: `docker/service-1/`
   - Not: `docker/service_1/` (underscore)
   - Pipeline handles both hyphens and underscores, but directory must exist

---

### ECR Permission Errors

#### Error: "An error occurred (AccessDeniedException) when calling the DescribeRepositories operation"

**Symptoms:**
- detect-changes job fails when checking ECR repositories
- Error mentions "AccessDeniedException" or "not authorized to perform: ecr:DescribeRepositories"

**Possible Causes:**
1. IAM role lacks ECR permissions
2. ECR permissions policy not attached to role
3. Permissions policy has incorrect resource ARN

**Solutions:**

1. **Verify Attached Policies:**
   ```bash
   aws iam list-attached-role-policies --role-name GitLabCIECRRole
   ```
   
   Should show the ECR permissions policy.

2. **Check Policy Permissions:**
   ```bash
   aws iam get-policy-version \
     --policy-arn arn:aws:iam::ACCOUNT_ID:policy/GitLabCIECRPolicy \
     --version-id v1
   ```
   
   Verify it includes:
   - `ecr:DescribeRepositories`
   - `ecr:GetAuthorizationToken`
   - Other ECR actions

3. **Attach Missing Policy:**
   ```bash
   aws iam attach-role-policy \
     --role-name GitLabCIECRRole \
     --policy-arn arn:aws:iam::ACCOUNT_ID:policy/GitLabCIECRPolicy
   ```

4. **Create Inline Policy (Alternative):**
   ```bash
   aws iam put-role-policy \
     --role-name GitLabCIECRRole \
     --policy-name ECRAccess \
     --policy-document file://ecr-permissions-policy.json
   ```

---

#### Error: "Error response from daemon: Get https://ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/v2/: denied"

**Symptoms:**
- Build job fails during docker push
- Error mentions "denied" or "authentication required"

**Possible Causes:**
1. ECR login failed
2. ECR authentication token expired
3. IAM role lacks ecr:GetAuthorizationToken permission

**Solutions:**

1. **Verify ECR Login:**
   
   Check build job log for:
   ```
   Logging in to ECR...
   Login Succeeded
   ```
   
   If missing, ECR login failed.

2. **Check GetAuthorizationToken Permission:**
   ```bash
   aws iam get-policy-version \
     --policy-arn arn:aws:iam::ACCOUNT_ID:policy/GitLabCIECRPolicy \
     --version-id v1 \
     --query 'PolicyVersion.Document.Statement[?Effect==`Allow`].Action' \
     --output text
   ```
   
   Should include `ecr:GetAuthorizationToken`.

3. **Test ECR Login Manually:**
   ```bash
   aws ecr get-login-password --region us-east-1 | \
     docker login --username AWS --password-stdin \
     ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
   ```

4. **Update Permissions Policy:**
   
   Ensure policy includes:
   ```json
   {
     "Effect": "Allow",
     "Action": [
       "ecr:GetAuthorizationToken"
     ],
     "Resource": "*"
   }
   ```

---

#### Error: "RepositoryNotFoundException" when pushing image

**Symptoms:**
- Build job fails during docker push
- Error mentions repository not found

**Possible Causes:**
1. ECR repository doesn't exist
2. Repository name mismatch
3. Wrong AWS region

**Solutions:**

1. **Verify Repository Exists:**
   ```bash
   aws ecr describe-repositories \
     --repository-names agentic-platform-service-1 \
     --region us-east-1
   ```

2. **Check Repository Name:**
   - Expected format: `agentic-platform-{service}`
   - Verify service name matches directory name

3. **Create Repository Manually:**
   ```bash
   aws ecr create-repository \
     --repository-name agentic-platform-service-1 \
     --region us-east-1
   ```

4. **Verify Region:**
   - Check AWS_REGION variable in GitLab
   - Ensure it matches where repositories are created

---

### Build Script Errors

#### Error: "deploy/build-container.sh: Permission denied"

**Symptoms:**
- Build job fails immediately
- Error mentions permission denied for build script

**Possible Causes:**
1. Build script is not executable
2. File permissions not preserved in git

**Solutions:**

1. **Make Script Executable:**
   ```bash
   chmod +x deploy/build-container.sh
   git add deploy/build-container.sh
   git commit -m "Make build script executable"
   git push
   ```

2. **Check Git Filemode:**
   ```bash
   git ls-files -s deploy/build-container.sh
   ```
   
   Should show `100755` (executable) not `100644`.

3. **Update Git Config:**
   ```bash
   git config core.filemode true
   git update-index --chmod=+x deploy/build-container.sh
   git commit -m "Fix build script permissions"
   git push
   ```

---

#### Error: "docker: command not found"

**Symptoms:**
- Build job fails when trying to run docker commands
- Error mentions "docker: command not found"

**Possible Causes:**
1. GitLab runner doesn't have Docker installed
2. Using wrong runner or image
3. Docker-in-Docker not configured

**Solutions:**

1. **Check Runner Configuration:**
   
   Verify `.gitlab-ci.yml` uses Docker image:
   ```yaml
   default:
     image: docker:24-cli
     services:
       - docker:24-dind
   ```

2. **Use Docker-in-Docker:**
   
   Ensure services section includes:
   ```yaml
   services:
     - docker:24-dind
   ```

3. **Check Runner Tags:**
   
   If using specific runners, ensure they support Docker:
   ```yaml
   build:
     tags:
       - docker
   ```

---

#### Error: "Service name not provided"

**Symptoms:**
- Build job fails immediately
- Error message: "Error: Service name not provided"

**Possible Causes:**
1. Service name not passed to build script
2. Matrix variable not configured correctly
3. Build list format is incorrect

**Solutions:**

1. **Check Matrix Configuration:**
   
   Verify in `.gitlab-ci.yml`:
   ```yaml
   parallel:
     matrix:
       - SERVICE: $SERVICES_TO_BUILD
   ```

2. **Check Build List Format:**
   
   In detect-changes job, verify:
   ```bash
   SERVICES_TO_BUILD='["service-1","service-2"]'
   ```
   
   Must be valid JSON array.

3. **Debug Service Variable:**
   
   Add to build job:
   ```yaml
   script:
     - echo "Service: $SERVICE"
     - ./deploy/build-container.sh $SERVICE
   ```

---

### Pipeline Configuration Errors

#### Error: "jobs:build config should contain at least one visible job"

**Symptoms:**
- Pipeline fails to start
- Error mentions build job configuration

**Possible Causes:**
1. Build job rules prevent it from running
2. No services to build and job is skipped
3. Rules configuration is incorrect

**Solutions:**

1. **Check Build Job Rules:**
   
   Verify rules allow job to run:
   ```yaml
   build:
     rules:
       - if: '$BUILD_COUNT == "0"'
         when: never
       - when: on_success
   ```

2. **This is Expected Behavior:**
   
   If no services need building, build stage should be skipped.
   Check summary job for confirmation.

3. **Force Build Job (Debug):**
   
   Temporarily remove rules:
   ```yaml
   build:
     # rules: ...  # Commented out
     when: always
   ```

---

#### Error: "Artifact not found"

**Symptoms:**
- Build or summary job fails
- Error mentions missing artifact or build.env

**Possible Causes:**
1. detect-changes job didn't upload artifact
2. Artifact expired
3. Dependencies not configured correctly

**Solutions:**

1. **Check Artifact Upload:**
   
   In detect-changes job log, look for:
   ```
   Uploading artifacts...
   Uploading artifacts to coordinator... ok
   ```

2. **Verify Dependencies:**
   
   Ensure build and summary jobs have:
   ```yaml
   needs:
     - job: detect-changes
       artifacts: true
   ```

3. **Check Artifact Path:**
   
   Verify detect-changes creates `build.env`:
   ```yaml
   artifacts:
     reports:
       dotenv: build.env
   ```

4. **Debug Artifact Content:**
   
   Add to build job:
   ```yaml
   script:
     - cat build.env || echo "build.env not found"
     - echo "SERVICES_TO_BUILD: $SERVICES_TO_BUILD"
   ```

---

### Common Issues Summary Table

| Error | Likely Cause | Quick Fix |
|-------|--------------|-----------|
| InvalidIdentityToken | OIDC provider not configured | Create OIDC provider in AWS |
| AccessDenied (AssumeRole) | Trust policy mismatch | Update trust policy with correct project path |
| AccessDenied (ECR) | Missing ECR permissions | Attach ECR policy to IAM role |
| Permission denied (script) | Script not executable | `chmod +x deploy/build-container.sh` |
| docker: command not found | Wrong runner/image | Use `docker:24-cli` image with `docker:24-dind` service |
| No changes detected | Files not in monitored paths | Check file paths match patterns |
| bad revision HEAD~1 | Shallow clone | Increase GIT_DEPTH |
| Repository not found | ECR repo doesn't exist | Create repository or let pipeline create it |
| Artifact not found | Missing dependencies | Add `needs` with `artifacts: true` |

---

### Getting Help

If you're still experiencing issues after trying these solutions:

1. **Check GitLab CI/CD Documentation:**
   - https://docs.gitlab.com/ee/ci/

2. **Check AWS Documentation:**
   - OIDC: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html
   - ECR: https://docs.aws.amazon.com/AmazonECR/latest/userguide/

3. **Enable Debug Logging:**
   
   Add to `.gitlab-ci.yml`:
   ```yaml
   variables:
     CI_DEBUG_TRACE: "true"
   ```
   
   **Warning:** This will expose all variables in logs. Remove after debugging.

4. **Collect Diagnostic Information:**
   - Pipeline ID and URL
   - Complete job logs (detect-changes, build, summary)
   - GitLab CI/CD variables (names only, not values)
   - AWS IAM role ARN
   - Error messages

5. **Test Components Individually:**
   - Test AWS OIDC authentication separately
   - Test ECR access with AWS CLI
   - Test build script locally
   - Test git diff logic locally

---

### Debug Mode

For comprehensive debugging, add this job to your pipeline:

```yaml
debug-pipeline:
  stage: .pre
  script:
    - echo "=== Environment ==="
    - echo "CI_COMMIT_SHA: $CI_COMMIT_SHA"
    - echo "CI_COMMIT_BEFORE_SHA: $CI_COMMIT_BEFORE_SHA"
    - echo "CI_MERGE_REQUEST_TARGET_BRANCH_SHA: $CI_MERGE_REQUEST_TARGET_BRANCH_SHA"
    - echo "AWS_REGION: $AWS_REGION"
    - echo "AWS_ROLE_ARN: $AWS_ROLE_ARN"
    - echo ""
    - echo "=== Git Status ==="
    - git log --oneline -5
    - echo ""
    - echo "=== Docker ==="
    - docker --version
    - echo ""
    - echo "=== AWS CLI ==="
    - aws --version
    - echo ""
    - echo "=== Services ==="
    - ls -la docker/
  rules:
    - when: manual
```

Run this job manually to collect diagnostic information.

---

## Conclusion

This testing guide provides comprehensive instructions for validating the GitLab CI/CD pipeline. Follow the sections in order:

1. Set up AWS OIDC integration
2. Configure GitLab repository
3. Set GitLab CI/CD variables
4. Run test scenarios
5. Validate results
6. Troubleshoot any issues

For questions or issues not covered in this guide, refer to the official GitLab and AWS documentation, or consult with your DevOps team.

---

**Document Version:** 1.0  
**Last Updated:** 2025-12-05  
**Maintained By:** DevOps Team
