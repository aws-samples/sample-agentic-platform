# GitLab CI/CD Deployment Guide

This guide walks you through setting up automated deployment of the ATX Container Test Runner using GitLab CI/CD with OIDC authentication.

## 🔐 Prerequisites

- GitLab account with CI/CD enabled
- AWS account with appropriate permissions
- Git installed locally

## 🚀 Step-by-Step Setup

### Step 1: AWS Infrastructure Setup

Run the automated setup script to create AWS resources:

```bash
# Make the script executable
chmod +x setup-gitlab-ci.sh

# Run the setup script
./setup-gitlab-ci.sh
```

This script creates:
- S3 buckets for source code and results
- OIDC Identity Provider for GitLab
- IAM role with secure temporary credentials
- ECR repository for Docker images

**Important:** Save the output values - you'll need them for GitLab configuration.

### Step 2: GitLab Repository Setup

1. **Create a new GitLab repository** or use an existing one

2. **Push this code to your GitLab repository:**
   ```bash
   git init
   git add .
   git commit -m "Initial ATX Container Test Runner setup"
   git remote add origin https://gitlab.com/your-username/atx-container-test-runner.git
   git push -u origin main
   ```

### Step 3: Configure GitLab CI/CD Variables

1. **Navigate to your GitLab project**
2. **Go to Settings → CI/CD → Variables**
3. **Add the following variables** (from setup script output):

| Variable Name | Value | Protected | Masked |
|---------------|-------|-----------|--------|
| `AWS_REGION` | Your AWS region (e.g., us-east-1) | ✅ | ❌ |
| `AWS_ACCOUNT_ID` | Your 12-digit AWS account ID | ✅ | ✅ |
| `AWS_ROLE_ARN` | IAM role ARN from setup script | ✅ | ❌ |
| `SOURCE_BUCKET` | S3 bucket for source code | ✅ | ❌ |
| `RESULTS_BUCKET` | S3 bucket for results | ✅ | ❌ |

**Security Notes:**
- Mark sensitive variables as "Protected" and "Masked"
- No AWS access keys needed - OIDC provides secure authentication
- Variables are only available to protected branches (main/master)

### Step 4: Verify GitLab Runner Configuration

Ensure your GitLab project has access to runners with Docker support:

1. **Go to Settings → CI/CD → Runners**
2. **Verify Docker executor is available**
3. **If using shared runners:** Ensure Docker-in-Docker is enabled
4. **If using custom runners:** Verify Docker is installed and configured

### Step 5: Trigger First Deployment

```bash
# Trigger the pipeline
git commit --allow-empty -m "Trigger initial deployment"
git push origin main
```

## 🔄 Pipeline Stages

The GitLab CI/CD pipeline includes these stages:

### 1. **Validate** 🔍
- Validates CloudFormation templates
- Checks script syntax
- Verifies configuration files

### 2. **Build** 🐳
- Builds Docker image
- Runs security scans
- Creates image tags

### 3. **Test** 🧪
- Runs smoke tests
- Validates ATX functionality
- Tests S3 integration

### 4. **Push** 📦
- Authenticates with AWS using OIDC
- Pushes Docker image to ECR
- Tags images appropriately

### 5. **Deploy** 🚀
- Deploys CloudFormation stack
- Updates ECS service
- Configures networking and security

### 6. **Verify** ✔️
- Checks deployment health
- Validates service endpoints
- Runs integration tests

## 🔧 Pipeline Configuration

The pipeline is configured in `.gitlab-ci.yml` with:

- **OIDC Authentication:** Secure, temporary AWS credentials
- **Docker-in-Docker:** For building container images
- **Conditional Deployment:** Only deploys from main branch
- **Manual Approval:** For production deployments
- **Rollback Support:** Automatic rollback on failure

## 🐛 Troubleshooting

### Common Issues

#### Pipeline Fails at Authentication
```
Error: Could not assume role with OIDC
```
**Solution:**
1. Verify OIDC Identity Provider is configured correctly
2. Check IAM role trust policy includes GitLab
3. Ensure variables are set correctly in GitLab

#### Docker Build Fails
```
Error: Cannot connect to Docker daemon
```
**Solution:**
1. Verify GitLab Runner has Docker support
2. Check if Docker-in-Docker service is enabled
3. Ensure sufficient resources for Docker builds

#### CloudFormation Deployment Fails
```
Error: Stack creation failed
```
**Solution:**
1. Check CloudWatch Logs for detailed errors
2. Verify IAM permissions for CloudFormation
3. Check resource limits and quotas
4. Review stack events in AWS Console

#### ECS Task Fails to Start
```
Error: Task stopped with exit code 1
```
**Solution:**
1. Check CloudWatch Logs: `/ecs/production-atx-test-runner`
2. Verify S3 bucket permissions
3. Check ECR image availability
4. Review task definition configuration

### Debug Commands

```bash
# Check pipeline logs
gitlab-ci-multi-runner exec docker validate

# Test Docker build locally
docker build -t atx-test-runner .

# Validate CloudFormation template
aws cloudformation validate-template --template-body file://deployment/cloudformation-complete-stack.yaml

# Check AWS authentication
aws sts get-caller-identity
```

## 🔒 Security Best Practices

### OIDC Configuration
- ✅ Use OIDC instead of long-lived access keys
- ✅ Limit token lifetime to 1 hour
- ✅ Restrict to specific branches (main/master)
- ✅ Use least privilege IAM policies

### GitLab Variables
- ✅ Mark sensitive variables as "Protected" and "Masked"
- ✅ Use environment-specific variable scopes
- ✅ Regularly rotate any manual credentials
- ✅ Audit variable access logs

### Container Security
- ✅ Enable ECR image scanning
- ✅ Use minimal base images
- ✅ Regularly update dependencies
- ✅ Scan for vulnerabilities in CI/CD

## 📊 Monitoring and Logging

### CloudWatch Integration
- **Application Logs:** `/ecs/production-atx-test-runner`
- **Pipeline Logs:** Available in GitLab CI/CD interface
- **AWS CloudTrail:** API call auditing
- **CloudWatch Metrics:** ECS and ECR metrics

### Alerts and Notifications
Configure GitLab notifications for:
- Pipeline failures
- Deployment completions
- Security scan results
- Performance issues

## 🔄 Updates and Maintenance

### Updating the Application
1. Make code changes
2. Commit and push to main branch
3. Pipeline automatically rebuilds and redeploys
4. Monitor deployment in GitLab and AWS Console

### Updating Infrastructure
1. Modify CloudFormation templates in `deployment/`
2. Test changes in development environment
3. Deploy via GitLab pipeline
4. Verify changes in AWS Console

### Rollback Procedure
If deployment fails:
1. Check pipeline logs for errors
2. Use GitLab's rollback feature if available
3. Or manually revert to previous commit:
   ```bash
   git revert HEAD
   git push origin main
   ```

## 🧹 Cleanup

To remove all resources:

### Via GitLab Pipeline
1. Go to **CI/CD → Pipelines**
2. Find latest pipeline
3. Click **destroy:stack** manual job
4. Click **Play** to execute

### Manual Cleanup
```bash
# Delete CloudFormation stack
aws cloudformation delete-stack --stack-name atx-test-runner --region us-east-1

# Delete ECR repository
aws ecr delete-repository --repository-name atx-test-runner --force --region us-east-1

# Delete S3 buckets (after emptying them)
aws s3 rb s3://your-source-bucket --force
aws s3 rb s3://your-results-bucket --force
```

## 📞 Support

For issues specific to GitLab CI/CD:
1. Check GitLab pipeline logs
2. Review this guide's troubleshooting section
3. Consult [GitLab CI/CD documentation](https://docs.gitlab.com/ee/ci/)
4. Check AWS CloudWatch Logs for runtime issues

For ATX-specific issues:
- See `docs/troubleshooting.md`
- Check `QUICK-REFERENCE.md`
- Review CloudWatch Logs

## 🎉 Success!

Once setup is complete, your GitLab repository will automatically:
- Build and test code changes
- Deploy to AWS ECS
- Run ATX transformations
- Store results in S3
- Provide detailed logging and monitoring

Happy coding! 🚀