# ATX Test Runner Deployment Guide

This guide provides step-by-step instructions for deploying the ATX Test Runner to AWS infrastructure.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [IAM Setup](#iam-setup)
3. [ECR Setup and Image Push](#ecr-setup-and-image-push)
4. [Deployment Options](#deployment-options)
   - [Option A: ECS on Fargate](#option-a-ecs-on-fargate)
   - [Option B: EKS (Kubernetes)](#option-b-eks-kubernetes)
   - [Option C: EC2 with Docker](#option-c-ec2-with-docker)
5. [Configuration](#configuration)
6. [Running Tasks](#running-tasks)
7. [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)
8. [Scaling and Optimization](#scaling-and-optimization)

## Prerequisites

Before deploying, ensure you have:

### Required Tools
- AWS CLI v2 installed and configured
- Docker installed and running
- Git (for cloning the repository)
- jq (for JSON processing, optional but recommended)

### AWS Account Requirements
- AWS account with appropriate permissions
- S3 buckets created:
  - Source bucket for Progress code
  - Results bucket for transformation outputs
- ECR repository access or permissions to create one

### Verify Prerequisites

```bash
# Check AWS CLI
aws --version
# Expected: aws-cli/2.x.x or higher

# Check Docker
docker --version
# Expected: Docker version 20.10.x or higher

# Check AWS credentials
aws sts get-caller-identity
# Should return your account ID and user/role

# Verify S3 buckets exist
aws s3 ls s3://your-source-bucket/
aws s3 ls s3://your-results-bucket/
```

## IAM Setup

### Step 1: Create IAM Roles

The ATX Test Runner requires two IAM roles:

1. **Task Execution Role**: For ECS to pull images and write logs
2. **Task Role**: For the container to access S3 buckets

#### Create Task Execution Role

```bash
# Create trust policy
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name atx-test-runner-execution-role \
  --assume-role-policy-document file://trust-policy.json

# Attach managed policy
aws iam attach-role-policy \
  --role-name atx-test-runner-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

#### Create Task Role with S3 Access

```bash
# Create S3 access policy
cat > s3-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::YOUR-SOURCE-BUCKET",
        "arn:aws:s3:::YOUR-SOURCE-BUCKET/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::YOUR-RESULTS-BUCKET",
        "arn:aws:s3:::YOUR-RESULTS-BUCKET/*"
      ]
    }
  ]
}
EOF

# Replace bucket names
sed -i 's/YOUR-SOURCE-BUCKET/your-actual-source-bucket/g' s3-policy.json
sed -i 's/YOUR-RESULTS-BUCKET/your-actual-results-bucket/g' s3-policy.json

# Create the role
aws iam create-role \
  --role-name atx-test-runner-task-role \
  --assume-role-policy-document file://trust-policy.json

# Attach S3 policy
aws iam put-role-policy \
  --role-name atx-test-runner-task-role \
  --policy-name s3-access \
  --policy-document file://s3-policy.json
```

### Step 2: Verify IAM Roles

```bash
# Get execution role ARN
aws iam get-role --role-name atx-test-runner-execution-role \
  --query 'Role.Arn' --output text

# Get task role ARN
aws iam get-role --role-name atx-test-runner-task-role \
  --query 'Role.Arn' --output text

# Save these ARNs - you'll need them later
```

## ECR Setup and Image Push

### Step 1: Build the Docker Image

```bash
# Clone the repository (if not already done)
git clone <repository-url>
cd atx-containers

# Build the image
docker build -t atx-test-runner:latest .

# Verify the build
docker images atx-test-runner
```

### Step 2: Push to ECR

Use the provided script for easy ECR push:

```bash
# Make the script executable
chmod +x scripts/push-to-ecr.sh

# Push to ECR (replace with your account ID and region)
./scripts/push-to-ecr.sh 123456789012 us-east-1

# The script will:
# - Authenticate to ECR
# - Create repository if needed
# - Tag the image
# - Push version and latest tags
# - Verify the push
```

#### Manual ECR Push (Alternative)

```bash
# Set variables
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-east-1"
REPO_NAME="atx-test-runner"
VERSION="0.1.0"

# Authenticate Docker to ECR
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Create ECR repository (if it doesn't exist)
aws ecr create-repository \
  --repository-name ${REPO_NAME} \
  --region ${AWS_REGION} \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256 \
  || echo "Repository already exists"

# Tag the image
docker tag atx-test-runner:latest \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}:${VERSION}

docker tag atx-test-runner:latest \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}:latest

# Push the images
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}:${VERSION}
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}:latest

# Verify
aws ecr describe-images \
  --repository-name ${REPO_NAME} \
  --region ${AWS_REGION}
```

## Deployment Options

### Option A: ECS on Fargate

This is the recommended option for most use cases.

#### Step 1: Create ECS Cluster

```bash
# Create cluster
aws ecs create-cluster \
  --cluster-name atx-test-runner-cluster \
  --capacity-providers FARGATE FARGATE_SPOT \
  --default-capacity-provider-strategy \
    capacityProvider=FARGATE,weight=1 \
    capacityProvider=FARGATE_SPOT,weight=4

# Enable Container Insights (optional)
aws ecs update-cluster-settings \
  --cluster atx-test-runner-cluster \
  --settings name=containerInsights,value=enabled
```

#### Step 2: Create CloudWatch Log Group

```bash
aws logs create-log-group \
  --log-group-name /ecs/atx-test-runner

# Set retention (optional)
aws logs put-retention-policy \
  --log-group-name /ecs/atx-test-runner \
  --retention-in-days 30
```

#### Step 3: Register Task Definition

```bash
# Navigate to deployment directory
cd deployment

# Update task definition with your values
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="us-east-1"
export IMAGE_VERSION="0.1.0"

# Replace placeholders
sed "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" ecs-task-definition.json | \
sed "s/REGION/${AWS_REGION}/g" | \
sed "s/VERSION/${IMAGE_VERSION}/g" > ecs-task-definition-updated.json

# Register the task definition
aws ecs register-task-definition \
  --cli-input-json file://ecs-task-definition-updated.json

# Verify registration
aws ecs describe-task-definition \
  --task-definition atx-test-runner \
  --query 'taskDefinition.taskDefinitionArn'
```

#### Step 4: Create VPC and Networking (if needed)

If you don't have a VPC with public subnets:

```bash
# Use CloudFormation template
aws cloudformation create-stack \
  --stack-name atx-test-runner-stack \
  --template-body file://cloudformation-complete-stack.yaml \
  --parameters \
    ParameterKey=SourceBucketName,ParameterValue=your-source-bucket \
    ParameterKey=ResultsBucketName,ParameterValue=your-results-bucket \
    ParameterKey=EnvironmentName,ParameterValue=production \
  --capabilities CAPABILITY_NAMED_IAM

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name atx-test-runner-stack

# Get outputs
aws cloudformation describe-stacks \
  --stack-name atx-test-runner-stack \
  --query 'Stacks[0].Outputs'
```

#### Step 5: Run the Task

```bash
# Set variables from CloudFormation outputs or your existing VPC
CLUSTER_NAME="atx-test-runner-cluster"
TASK_DEFINITION="atx-test-runner"
SUBNET_1="subnet-xxxxx"
SUBNET_2="subnet-yyyyy"
SECURITY_GROUP="sg-zzzzz"

# Run the task
aws ecs run-task \
  --cluster ${CLUSTER_NAME} \
  --task-definition ${TASK_DEFINITION} \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[${SUBNET_1},${SUBNET_2}],
    securityGroups=[${SECURITY_GROUP}],
    assignPublicIp=ENABLED
  }" \
  --region ${AWS_REGION}

# Get task ARN from output
TASK_ARN=$(aws ecs list-tasks \
  --cluster ${CLUSTER_NAME} \
  --query 'taskArns[0]' \
  --output text)

# Monitor task
aws ecs describe-tasks \
  --cluster ${CLUSTER_NAME} \
  --tasks ${TASK_ARN}
```

### Option B: EKS (Kubernetes)

#### Step 1: Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --name your-eks-cluster \
  --region us-east-1

# Verify connection
kubectl get nodes
```

#### Step 2: Create IAM Role for Service Account (IRSA)

```bash
# Create OIDC provider (if not already done)
eksctl utils associate-iam-oidc-provider \
  --cluster your-eks-cluster \
  --approve

# Create service account with IAM role
eksctl create iamserviceaccount \
  --name atx-test-runner \
  --namespace atx-test-runner \
  --cluster your-eks-cluster \
  --attach-policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/atx-s3-access \
  --approve
```

#### Step 3: Deploy to Kubernetes

```bash
# Update deployment YAML
cd deployment
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="us-east-1"
export IMAGE_VERSION="0.1.0"

sed "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" kubernetes-deployment.yaml | \
sed "s/REGION/${AWS_REGION}/g" | \
sed "s/VERSION/${IMAGE_VERSION}/g" > kubernetes-deployment-updated.yaml

# Apply configuration
kubectl apply -f kubernetes-deployment-updated.yaml

# Verify deployment
kubectl get all -n atx-test-runner

# Check job status
kubectl get jobs -n atx-test-runner
kubectl describe job atx-test-runner-job -n atx-test-runner

# View logs
kubectl logs -n atx-test-runner job/atx-test-runner-job -f
```

### Option C: EC2 with Docker

For running on EC2 instances:

#### Step 1: Launch EC2 Instance

```bash
# Launch instance with appropriate IAM role
aws ec2 run-instances \
  --image-id ami-xxxxx \
  --instance-type t3.large \
  --iam-instance-profile Name=atx-test-runner-instance-profile \
  --user-data file://examples/ec2-user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=atx-test-runner}]'
```

#### Step 2: SSH and Run Container

```bash
# SSH to instance
ssh ec2-user@<instance-ip>

# Authenticate to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com

# Pull image
docker pull ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/atx-test-runner:latest

# Run container
docker run \
  -e AWS_DEFAULT_REGION=us-east-1 \
  ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/atx-test-runner:latest \
  --csv-file /config/repos.csv \
  --mode parallel \
  --max-jobs 4
```

## Configuration

### CSV Configuration File

Create a CSV file with your repository configurations:

```csv
s3_path,build_command,transformation_name,output_s3_path
s3://source-bucket/customer1/folder1/,noop,Comprehensive-Codebase-Analysis,s3://results-bucket/customer1/folder1/
s3://source-bucket/customer1/folder2/,noop,Comprehensive-Codebase-Analysis,s3://results-bucket/customer1/folder2/
s3://source-bucket/customer2/folder1/,noop,Comprehensive-Codebase-Analysis,s3://results-bucket/customer2/folder1/
```

Upload to S3 or mount as ConfigMap (Kubernetes):

```bash
# Upload to S3
aws s3 cp repos.csv s3://your-config-bucket/repos.csv

# Or create Kubernetes ConfigMap
kubectl create configmap atx-test-runner-config \
  --from-file=repos.csv \
  -n atx-test-runner
```

### Environment Variables

Configure the following environment variables:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| AWS_DEFAULT_REGION | AWS region | - | Yes |
| AWS_REGION | AWS region (alternative) | - | Yes |
| ATX_LOG_LEVEL | Logging level | INFO | No |
| SOURCE_BUCKET | Source S3 bucket | - | No |
| RESULTS_BUCKET | Results S3 bucket | - | No |

## Running Tasks

### One-Time Execution

```bash
# ECS
aws ecs run-task \
  --cluster atx-test-runner-cluster \
  --task-definition atx-test-runner \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}"

# Kubernetes
kubectl create job atx-manual-run \
  --from=cronjob/atx-test-runner-scheduled \
  -n atx-test-runner
```

### Scheduled Execution

#### ECS with EventBridge

```bash
# Create EventBridge rule
aws events put-rule \
  --name atx-daily-run \
  --schedule-expression "cron(0 2 * * ? *)" \
  --state ENABLED

# Add ECS task as target
aws events put-targets \
  --rule atx-daily-run \
  --targets "Id"="1","Arn"="arn:aws:ecs:us-east-1:${AWS_ACCOUNT_ID}:cluster/atx-test-runner-cluster","RoleArn"="arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsEventsRole","EcsParameters"="{TaskDefinitionArn=arn:aws:ecs:us-east-1:${AWS_ACCOUNT_ID}:task-definition/atx-test-runner,TaskCount=1,LaunchType=FARGATE,NetworkConfiguration={awsvpcConfiguration={Subnets=[subnet-xxx],SecurityGroups=[sg-xxx],AssignPublicIp=ENABLED}}}"
```

#### Kubernetes CronJob

The Kubernetes deployment includes a CronJob that runs daily at 2 AM:

```bash
# View CronJob
kubectl get cronjobs -n atx-test-runner

# Manually trigger
kubectl create job atx-manual-$(date +%s) \
  --from=cronjob/atx-test-runner-scheduled \
  -n atx-test-runner
```

## Monitoring and Troubleshooting

### View Logs

#### ECS CloudWatch Logs

```bash
# Tail logs
aws logs tail /ecs/atx-test-runner --follow

# Get specific task logs
aws logs get-log-events \
  --log-group-name /ecs/atx-test-runner \
  --log-stream-name atx/atx-test-runner/<task-id>
```

#### Kubernetes Logs

```bash
# View job logs
kubectl logs -n atx-test-runner job/atx-test-runner-job -f

# View pod logs
kubectl logs -n atx-test-runner <pod-name> -f

# View previous pod logs (if crashed)
kubectl logs -n atx-test-runner <pod-name> --previous
```

### Check Task Status

#### ECS

```bash
# List running tasks
aws ecs list-tasks --cluster atx-test-runner-cluster

# Describe task
aws ecs describe-tasks \
  --cluster atx-test-runner-cluster \
  --tasks <task-arn>
```

#### Kubernetes

```bash
# Check job status
kubectl get jobs -n atx-test-runner

# Describe job
kubectl describe job atx-test-runner-job -n atx-test-runner

# Check pod status
kubectl get pods -n atx-test-runner
```

### Common Issues

See the [Troubleshooting Guide](troubleshooting.md) for detailed solutions.

## Scaling and Optimization

### Vertical Scaling

Adjust CPU and memory based on workload:

```bash
# Update task definition with more resources
# Edit ecs-task-definition.json:
# "cpu": "4096",
# "memory": "8192"

# Re-register
aws ecs register-task-definition \
  --cli-input-json file://ecs-task-definition.json
```

### Horizontal Scaling

Run multiple tasks in parallel:

```bash
# Run multiple tasks
for i in {1..5}; do
  aws ecs run-task \
    --cluster atx-test-runner-cluster \
    --task-definition atx-test-runner \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}"
done
```

### Cost Optimization

1. **Use Fargate Spot**: 70% cheaper than regular Fargate
2. **Right-size resources**: Monitor and adjust CPU/memory
3. **Use lifecycle policies**: Clean up old ECR images
4. **Schedule during off-peak**: Run during cheaper hours

## Next Steps

1. Review [Monitoring Guide](troubleshooting.md#monitoring)
2. Set up [Alerting](troubleshooting.md#alerting)
3. Configure [Auto-scaling](troubleshooting.md#auto-scaling)
4. Implement [CI/CD Pipeline](../examples/ci-cd-integration.sh)

## Support

For issues or questions:
- Check [Troubleshooting Guide](troubleshooting.md)
- Review [Examples](../examples/)
- Check CloudWatch Logs
- Verify IAM permissions
