# ATX Test Runner Deployment Templates

This directory contains deployment templates for running the ATX Test Runner on AWS infrastructure.

## Available Templates

### 1. ECS Task Definition (JSON)
- **File**: `ecs-task-definition.json`
- **Purpose**: Standalone ECS task definition for Fargate
- **Use Case**: Quick deployment to existing ECS cluster

### 2. Kubernetes Deployment (YAML)
- **File**: `kubernetes-deployment.yaml`
- **Purpose**: Complete Kubernetes deployment including Job and CronJob
- **Use Case**: EKS or self-managed Kubernetes clusters

### 3. CloudFormation Complete Stack (YAML)
- **File**: `cloudformation-complete-stack.yaml`
- **Purpose**: Complete infrastructure including VPC, ECS cluster, IAM roles
- **Use Case**: New AWS environment setup

### 4. Terraform Configuration
- **Directory**: `terraform/`
- **Files**: `main.tf`, `variables.tf`, `outputs.tf`
- **Purpose**: Infrastructure as Code with Terraform
- **Use Case**: Terraform-managed infrastructure

## Quick Start

### Option 1: ECS Task Definition

1. Update the task definition with your values:
```bash
sed -i 's/ACCOUNT_ID/123456789012/g' ecs-task-definition.json
sed -i 's/REGION/us-east-1/g' ecs-task-definition.json
sed -i 's/VERSION/0.1.0/g' ecs-task-definition.json
```

2. Register the task definition:
```bash
aws ecs register-task-definition \
  --cli-input-json file://ecs-task-definition.json
```

3. Run the task:
```bash
aws ecs run-task \
  --cluster my-cluster \
  --task-definition atx-test-runner \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}"
```

### Option 2: Kubernetes

1. Update the deployment YAML:
```bash
sed -i 's/ACCOUNT_ID/123456789012/g' kubernetes-deployment.yaml
sed -i 's/REGION/us-east-1/g' kubernetes-deployment.yaml
sed -i 's/VERSION/0.1.0/g' kubernetes-deployment.yaml
```

2. Apply the configuration:
```bash
kubectl apply -f kubernetes-deployment.yaml
```

3. Check job status:
```bash
kubectl get jobs -n atx-test-runner
kubectl logs -n atx-test-runner job/atx-test-runner-job
```

### Option 3: CloudFormation

1. Create the stack:
```bash
aws cloudformation create-stack \
  --stack-name atx-test-runner \
  --template-body file://cloudformation-complete-stack.yaml \
  --parameters \
    ParameterKey=SourceBucketName,ParameterValue=my-source-bucket \
    ParameterKey=ResultsBucketName,ParameterValue=my-results-bucket \
  --capabilities CAPABILITY_NAMED_IAM
```

2. Wait for stack creation:
```bash
aws cloudformation wait stack-create-complete \
  --stack-name atx-test-runner
```

3. Get outputs:
```bash
aws cloudformation describe-stacks \
  --stack-name atx-test-runner \
  --query 'Stacks[0].Outputs'
```

### Option 4: Terraform

1. Navigate to terraform directory:
```bash
cd terraform
```

2. Copy and edit variables:
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

3. Initialize Terraform:
```bash
terraform init
```

4. Plan the deployment:
```bash
terraform plan
```

5. Apply the configuration:
```bash
terraform apply
```

6. Get outputs:
```bash
terraform output
```

## Configuration Parameters

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| AWS Account ID | Your AWS account ID | - | Yes |
| AWS Region | AWS region for deployment | us-east-1 | Yes |
| Image Version | Docker image tag | latest | No |
| Source Bucket | S3 bucket with source code | - | Yes |
| Results Bucket | S3 bucket for results | - | Yes |
| Task CPU | CPU units (1024 = 1 vCPU) | 2048 | No |
| Task Memory | Memory in MB | 4096 | No |
| Max Parallel Jobs | Concurrent transformations | 4 | No |

### ECS-Specific Parameters

- **Network Mode**: awsvpc (required for Fargate)
- **Launch Type**: FARGATE or FARGATE_SPOT
- **Requires Compatibilities**: FARGATE

### Kubernetes-Specific Parameters

- **Namespace**: atx-test-runner
- **Service Account**: atx-test-runner (with IAM role annotation)
- **Restart Policy**: OnFailure
- **TTL After Finished**: 86400 seconds (24 hours)

## IAM Permissions Required

### Task Role Permissions
The ECS task needs the following S3 permissions:

**Source Bucket (Read)**:
- `s3:GetObject`
- `s3:ListBucket`

**Results Bucket (Write)**:
- `s3:PutObject`
- `s3:PutObjectAcl`
- `s3:ListBucket`

### Execution Role Permissions
The ECS execution role needs:
- `AmazonECSTaskExecutionRolePolicy` (managed policy)
- ECR pull permissions (included in managed policy)
- CloudWatch Logs write permissions (included in managed policy)

## Networking Requirements

### ECS/Fargate
- VPC with public or private subnets
- Internet access (via Internet Gateway or NAT Gateway)
- Security group allowing outbound HTTPS (443) for S3 and ECR

### Kubernetes/EKS
- EKS cluster with worker nodes or Fargate profile
- Service account with IAM role (IRSA)
- Network policies allowing S3 access

## Cost Optimization

### Use Fargate Spot
CloudFormation and Terraform templates include Fargate Spot capacity providers with 80% weight:
- 80% of tasks run on Spot (cheaper)
- 20% of tasks run on regular Fargate (reliability)

### Right-Size Resources
Adjust CPU and memory based on your workload:
- Small repos: 1024 CPU / 2048 MB
- Medium repos: 2048 CPU / 4096 MB
- Large repos: 4096 CPU / 8192 MB

### Use Lifecycle Policies
ECR lifecycle policies automatically clean up old images:
- Keep last 10 images
- Reduces storage costs

## Monitoring and Logging

### CloudWatch Logs
All templates configure CloudWatch Logs:
- Log Group: `/ecs/atx-test-runner` or `/ecs/{environment}-atx-test-runner`
- Retention: 30 days
- Stream Prefix: `atx`

### Container Insights
ECS clusters have Container Insights enabled for:
- CPU and memory utilization
- Network metrics
- Task-level metrics

### Viewing Logs

**ECS**:
```bash
aws logs tail /ecs/atx-test-runner --follow
```

**Kubernetes**:
```bash
kubectl logs -n atx-test-runner -f job/atx-test-runner-job
```

## Troubleshooting

### Task Fails to Start

1. Check IAM permissions:
```bash
aws iam get-role --role-name atx-task-role
aws iam get-role-policy --role-name atx-task-role --policy-name s3-access
```

2. Verify ECR image exists:
```bash
aws ecr describe-images --repository-name atx-test-runner
```

3. Check CloudWatch logs:
```bash
aws logs tail /ecs/atx-test-runner --follow
```

### S3 Access Denied

1. Verify bucket permissions:
```bash
aws s3 ls s3://my-source-bucket/
aws s3 ls s3://my-results-bucket/
```

2. Check task role policy:
```bash
aws iam get-role-policy --role-name atx-task-role --policy-name s3-access
```

### Network Issues

1. Verify security group allows outbound HTTPS:
```bash
aws ec2 describe-security-groups --group-ids sg-xxx
```

2. Check subnet has internet access:
```bash
aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=subnet-xxx"
```

## Cleanup

### CloudFormation
```bash
aws cloudformation delete-stack --stack-name atx-test-runner
```

### Terraform
```bash
cd terraform
terraform destroy
```

### Kubernetes
```bash
kubectl delete namespace atx-test-runner
```

### Manual ECS
```bash
# Deregister task definition
aws ecs deregister-task-definition --task-definition atx-test-runner:1

# Delete cluster (if empty)
aws ecs delete-cluster --cluster my-cluster
```

## Next Steps

1. Review the [Deployment Guide](../docs/deployment.md) for detailed instructions
2. Check [Troubleshooting Guide](../docs/troubleshooting.md) for common issues
3. See [Examples](../examples/) for sample configurations
4. Read [Build and Test Guide](../docs/build-and-test.md) for local testing

## Support

For issues or questions:
1. Check the troubleshooting guide
2. Review CloudWatch logs
3. Verify IAM permissions
4. Check network connectivity
