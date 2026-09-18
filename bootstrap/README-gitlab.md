# GitLab CI/CD OIDC Integration for AWS ECR

This CloudFormation template enables secure, credential-free authentication between GitLab CI/CD pipelines and AWS using OpenID Connect (OIDC). It allows your GitLab pipelines to push container images to Amazon ECR without storing long-lived AWS credentials.

## 🎯 What This Template Creates

- **OIDC Identity Provider**: Establishes trust between AWS and GitLab.com
- **IAM Role**: Provides temporary credentials to GitLab CI/CD pipelines
- **IAM Policy**: Grants permissions to create ECR repositories and push container images

## 📋 Prerequisites

- AWS account with permissions to create IAM resources
- GitLab project hosted on gitlab.com
- AWS CLI installed and configured (for deployment)

## 🚀 Deployment

### Step 1: Gather Required Information

From your GitLab project URL `https://gitlab.com/GROUP/PROJECT`:
- **GitLabGroup**: The group or namespace (e.g., `my-company`)
- **GitLabProject**: The project name (e.g., `my-app`)

### Step 2: Deploy the CloudFormation Stack

```bash
aws cloudformation create-stack \
  --stack-name gitlab-ci-oidc \
  --template-body file://gitlab-bootstrap.yaml \
  --parameters \
    ParameterKey=GitLabGroup,ParameterValue=YOUR_GROUP \
    ParameterKey=GitLabProject,ParameterValue=YOUR_PROJECT \
    ParameterKey=ECRRepositoryPrefix,ParameterValue=my-prefix \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

**Parameters:**
- `GitLabGroup` (Required): Your GitLab group/namespace
- `GitLabProject` (Required): Your GitLab project name
- `ECRRepositoryPrefix` (Optional): Prefix for ECR repositories. Leave empty to use project name.

### Step 3: Get Stack Outputs

```bash
aws cloudformation describe-stacks \
  --stack-name gitlab-ci-oidc \
  --query 'Stacks[0].Outputs' \
  --region us-east-1
```

Copy the `GitLabCIRoleArn` value.

## ⚙️ GitLab Configuration

### Add CI/CD Variables

1. Go to your GitLab project: **Settings > CI/CD > Variables**
2. Add these variables:

| Variable | Value | Protected | Masked |
|----------|-------|-----------|--------|
| `AWS_ROLE_ARN` | (ARN from stack outputs) | ✅ | ❌ |
| `AWS_REGION` | Your AWS region (e.g., `us-east-1`) | ❌ | ❌ |
| `AWS_ACCOUNT_ID` | Your 12-digit AWS account ID | ❌ | ❌ |

### Create `.gitlab-ci.yml`

Add this to your GitLab project:

```yaml
image: docker:latest

services:
  - docker:dind

variables:
  AWS_DEFAULT_REGION: $AWS_REGION
  ECR_REGISTRY: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
  IMAGE_NAME: my-prefix/my-app

before_script:
  - apk add --no-cache aws-cli

stages:
  - build
  - push

build-image:
  stage: build
  script:
    - docker build -t $IMAGE_NAME:$CI_COMMIT_SHORT_SHA .
    - docker tag $IMAGE_NAME:$CI_COMMIT_SHORT_SHA $IMAGE_NAME:latest

push-to-ecr:
  stage: push
  id_tokens:
    GITLAB_OIDC_TOKEN:
      aud: sts.amazonaws.com
  script:
    # Assume the IAM role using OIDC token
    - |
      export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" \
      $(aws sts assume-role-with-web-identity \
      --role-arn ${AWS_ROLE_ARN} \
      --role-session-name "gitlab-${CI_PROJECT_ID}-${CI_PIPELINE_ID}" \
      --web-identity-token ${GITLAB_OIDC_TOKEN} \
      --duration-seconds 3600 \
      --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
      --output text))
    
    # Login to ECR
    - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
    
    # Create repository if it doesn't exist
    - aws ecr describe-repositories --repository-names $IMAGE_NAME --region $AWS_REGION || aws ecr create-repository --repository-name $IMAGE_NAME --region $AWS_REGION
    
    # Tag and push
    - docker tag $IMAGE_NAME:latest $ECR_REGISTRY/$IMAGE_NAME:$CI_COMMIT_SHORT_SHA
    - docker tag $IMAGE_NAME:latest $ECR_REGISTRY/$IMAGE_NAME:latest
    - docker push $ECR_REGISTRY/$IMAGE_NAME:$CI_COMMIT_SHORT_SHA
    - docker push $ECR_REGISTRY/$IMAGE_NAME:latest
  only:
    - main
    - develop
    - tags
```

## 🔒 Security Features

### Branch Restrictions
The IAM role can only be assumed by pipelines running on:
- `main` branch
- `develop` branch
- Tags (e.g., `v1.0.0`)
- Merge request branches

### ECR Repository Scoping
Permissions are limited to ECR repositories matching the configured prefix:
- With prefix `my-prefix`: Can access `my-prefix/*` repositories
- Without prefix: Can access `{project-name}/*` repositories

### Temporary Credentials
- No long-lived AWS credentials stored in GitLab
- Credentials expire after 1 hour
- Each pipeline run gets unique credentials

## 🧪 Testing

### Quick Test

Create a simple test pipeline:

```yaml
test-aws-connection:
  stage: test
  id_tokens:
    GITLAB_OIDC_TOKEN:
      aud: sts.amazonaws.com
  script:
    - apk add --no-cache aws-cli
    - |
      export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" \
      $(aws sts assume-role-with-web-identity \
      --role-arn ${AWS_ROLE_ARN} \
      --role-session-name "gitlab-test" \
      --web-identity-token ${GITLAB_OIDC_TOKEN} \
      --duration-seconds 3600 \
      --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
      --output text))
    - echo "✅ Successfully authenticated to AWS!"
    - aws sts get-caller-identity
    - aws ecr describe-repositories --region $AWS_REGION || echo "No repositories yet"
```

## 🔧 Troubleshooting

### Error: "Couldn't retrieve verification key"
- Ensure you're using gitlab.com (not self-hosted GitLab)
- Verify the OIDC provider was created successfully in IAM

### Error: "Not authorized to perform sts:AssumeRoleWithWebIdentity"
- Check that your GitLab project path matches the parameters
- Verify you're running on an allowed branch (main, develop, tags)
- Ensure the `id_tokens` section is in your `.gitlab-ci.yml`

### Error: "Access Denied" when pushing to ECR
- Verify the repository name matches the configured prefix
- Check that the IAM policy is attached to the role

## 📚 Additional Resources

- [GitLab OIDC Documentation](https://docs.gitlab.com/ee/ci/cloud_services/)
- [AWS IAM OIDC Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [Amazon ECR Documentation](https://docs.aws.amazon.com/ecr/)

## 🗑️ Cleanup

To remove all resources:

```bash
aws cloudformation delete-stack \
  --stack-name gitlab-ci-oidc \
  --region us-east-1
```

## 📝 License

This template is provided as-is for use with AWS and GitLab integration.
