# GitLab CI/CD Pipeline Setup Guide

This guide will help you set up the GitLab CI/CD pipeline for building and pushing Docker containers to AWS ECR.

## Files Included

1. `.gitlab-ci.yml` - GitLab CI/CD pipeline configuration
2. `deploy/build-container-gitlab.sh` - Docker build script
3. `script/setup_aws_oidc.sh` - AWS OIDC setup script
4. `docs/TESTING_GUIDE.md` - Detailed testing guide

## Prerequisites

- GitLab repository with your code
- AWS account with permissions to create IAM roles and ECR repositories
- AWS CLI installed and configured locally

## Setup Steps

### 1. Add Files to Your Repository

Copy these files to your GitLab repository:
- `.gitlab-ci.yml` (root directory)
- `deploy/build-container-gitlab.sh`
- `script/setup_aws_oidc.sh`

Commit and push to GitLab:
```bash
git add .gitlab-ci.yml deploy/build-container-gitlab.sh script/setup_aws_oidc.sh
git commit -m "Add GitLab CI/CD pipeline for container builds"
git push origin main
```

### 2. Configure AWS OIDC Trust

Run the setup script locally (requires AWS CLI configured):

```bash
chmod +x script/setup_aws_oidc.sh
./script/setup_aws_oidc.sh YOUR_GITLAB_PROJECT_PATH
```

**Example:**
```bash
./script/setup_aws_oidc.sh mycompany/myproject
```

The script will output an `AWS_ROLE_ARN` - **save this value**.

### 3. Configure GitLab CI/CD Variables

Go to your GitLab project:
1. Navigate to: **Settings → CI/CD → Variables**
2. Click **"Add variable"**
3. Add these two variables:

**Variable 1:**
- Key: `AWS_ROLE_ARN`
- Value: `arn:aws:iam::YOUR_ACCOUNT_ID:role/GitLabCIRole` (from step 2)
- Type: Variable
- Protect variable: ☐ (unchecked)
- Mask variable: ☑ (checked)

**Variable 2:**
- Key: `AWS_REGION`
- Value: `us-east-1` (or your preferred region)
- Type: Variable
- Protect variable: ☐ (unchecked)
- Mask variable: ☐ (unchecked)

### 4. Test the Pipeline

Push a commit to trigger the pipeline:
```bash
git commit --allow-empty -m "Test pipeline"
git push origin main
```

Or manually trigger it:
1. Go to: **CI/CD → Pipelines**
2. Click **"Run pipeline"**
3. Select branch: `main`
4. Click **"Run pipeline"**

## How It Works

### Automatic Triggers

The pipeline runs automatically on:
- Push to `main` branch
- Push to `develop` branch
- Push of version tags (v*)
- Merge requests

### Service Discovery

The pipeline automatically discovers services by scanning:
- `src/agentic_platform/agent/*/Dockerfile`
- `docker/*/Dockerfile` (fallback)

### Change Detection

The pipeline intelligently builds only changed services:
- **Core changes**: Rebuilds all services if core dependencies change
- **Service changes**: Rebuilds only affected services
- **New services**: Automatically builds services with missing ECR repositories

### Parallel Builds

All services build in parallel for faster execution.

### ECR Repository Management

The pipeline automatically:
- Creates ECR repositories if they don't exist
- Uses naming pattern: `agentic-platform-{service-name}`
- Tags images with commit SHA and `latest`

## Pipeline Stages

1. **detect-changes**: Discovers services and determines what to build
2. **build**: Builds and pushes Docker images to ECR in parallel
3. **summary**: Shows build results

## Manual Triggering Options

When manually triggering the pipeline, you can set the `MANUAL_SERVICES` variable:

- `all` - Build all services
- `changed` - Build only changed services (default)
- `service1,service2` - Build specific services (comma-separated)

## Monitoring

View pipeline execution:
- Go to: **CI/CD → Pipelines**
- Click on a pipeline to see detailed logs
- Each service builds in parallel with its own log section

## Troubleshooting

### Pipeline fails with "Incorrect token audience"
- Verify the OIDC provider audience in AWS IAM is set to `https://gitlab.com`
- Re-run the setup script: `./script/setup_aws_oidc.sh YOUR_PROJECT_PATH`

### Pipeline fails with "Access Denied"
- Verify `AWS_ROLE_ARN` variable is set correctly in GitLab
- Check the IAM role trust policy includes your GitLab project path

### No services discovered
- Verify Dockerfiles exist in `src/agentic_platform/agent/{service}/Dockerfile`
- Check the detect-changes job logs for discovery output

### Docker build fails
- Verify the Dockerfile paths are correct
- Check that all source files referenced in Dockerfile exist
- Review the build job logs for specific errors

## AWS Resources Created

The setup script creates:
1. **OIDC Identity Provider**: `gitlab.com`
2. **IAM Role**: `GitLabCIRole` (or custom name)
3. **IAM Policy**: Permissions for ECR operations
4. **ECR Repositories**: Created automatically during first build

## Security Notes

- No AWS credentials are stored in GitLab
- Uses OIDC for secure, temporary authentication
- IAM role is scoped to your specific GitLab project
- ECR permissions are limited to `agentic-platform-*` repositories

## Support

For detailed testing instructions, see `docs/TESTING_GUIDE.md`

For issues or questions, contact your DevOps team.
