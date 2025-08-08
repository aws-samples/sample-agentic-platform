# Infrastructure Deployment Guide

> **⚠️ DEPRECATION NOTICE**: The `infrastructure/terraform/` directory is being deprecated in favor of the modular stack approach in `infrastructure/stacks/` and `infrastructure/modules/`.

## Overview

This infrastructure deploys a complete agentic platform on AWS using Terraform. The platform includes EKS, PostgreSQL Aurora, Redis, Cognito authentication, and supporting services.

## Deployment Options

### Option 1: Automated Bootstrap (Recommended)

Use the automated bootstrap for 1-click deployment (WIP). This approach:
- Deploys infrastructure from within the VPC for security
- Keeps EKS cluster private (never publicly accessible)
- Uses CI/CD pipeline for deployment
- Sets up VPC automatically

```bash
# See bootstrap/README.md for detailed instructions
cd bootstrap/
# Follow bootstrap deployment guide
```

### Option 2: Manual Deployment

For testing and development purposes only. **Never use in production.**

## Prerequisites

1. **AWS CLI configured** with appropriate permissions
2. **Terraform >= 1.0** installed
3. **S3 bucket** for Terraform state storage

## Step 1: Foundation Stack (Optional)

If you don't have an existing VPC, deploy the foundation stack first:

```bash
cd infrastructure/stacks/foundation/
terraform init
terraform plan
terraform apply
```

## Step 2: Backend Configuration

Create a `backend.tf` file in the platform-eks stack:

```hcl
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "agentic-platform/terraform.tfstate"
    region = "us-west-2"
    encrypt = true
  }
}
```

## Step 3: Configure Variables

Create `terraform.tfvars` in `infrastructure/stacks/platform-eks/`:

```hcl
# Core Configuration
aws_region  = "us-west-2"
environment = "dev"

# Networking (from foundation stack outputs or existing VPC)
vpc_id         = "vpc-xxxxxxxxx"
vpc_cidr_block = "10.0.0.0/16"
private_subnet_ids = [
  "subnet-xxxxxxxxx",
  "subnet-yyyyyyyyy"
]
public_subnet_ids = [
  "subnet-zzzzzzzzz",
  "subnet-aaaaaaaaa"
]

# EKS Access Configuration
enable_eks_public_access = false  # Set to true ONLY for local testing
deploy_inside_vpc = true          # Set to false ONLY for local testing

# Admin Access (replace with your IAM role ARN)
additional_admin_role_arns = [
  "arn:aws:iam::ACCOUNT-ID:role/YourAdminRole"
]
```

### Getting Variable Values

- **VPC/Subnet IDs**: From foundation stack outputs or existing VPC
- **Admin Role ARN**: Your current IAM role ARN from `aws sts get-caller-identity`
- **Account ID**: From `aws sts get-caller-identity`

## Step 4: Deploy Platform Stack

```bash
cd infrastructure/stacks/platform-eks/
terraform init
terraform plan
terraform apply
```

## Step 5: PostgreSQL Users Setup

After the platform stack is deployed, you need to create PostgreSQL users, databases, and permissions using the `postgres-users` stack. This is a **one-time setup**.

### Option A: Running from Local Machine (Port Forwarding Required)

If running from your local machine, you need to port forward through the bastion host:

```bash
# 1. Get the bastion instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*bastion-instance*" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

# 2. Start port forwarding session (replace <aurora-writer-endpoint> with actual endpoint)
aws ssm start-session \
  --target $INSTANCE_ID \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "portNumber=5432,localPortNumber=5432,host=<aurora-writer-endpoint>"

# 3. In a new terminal, run the postgres-users stack with local proxy enabled
cd infrastructure/stacks/postgres-users/
terraform init
terraform apply -var="use_local_proxy=true"
```

### Option B: Running from Bastion Host

If running directly from the bastion host, you can execute terraform directly:

```bash
# SSH into bastion host first, then:
cd infrastructure/stacks/postgres-users/
terraform init
terraform apply  # use_local_proxy defaults to false
```

### Getting the Aurora Writer Endpoint

You can get the Aurora writer endpoint from the platform-eks stack outputs:

```bash
cd infrastructure/stacks/platform-eks/
terraform output postgres_cluster_endpoint
```

## Important Security Notes

### EKS Access Configuration

The Kubernetes module requires **exactly one** of these configurations:

✅ **Secure (Recommended)**:
- `enable_eks_public_access = false`
- `deploy_inside_vpc = true`

✅ **Testing Only**:
- `enable_eks_public_access = true`
- `deploy_inside_vpc = false`

❌ **Invalid Configurations**:
- Both `true` (conflicting)
- Both `false` (no access to K8s API)

### Public Access Warning

**⚠️ CRITICAL**: Setting `enable_eks_public_access = true` should **ONLY** be used in:
- Sandbox accounts
- Local testing scenarios
- **NEVER in production environments**

## Cost Optimization

The stack uses minimal defaults to keep costs low:
- `t3.medium` EKS nodes (4 nodes)
- `db.t4g.medium` Aurora instances (2 instances)
- `cache.t4g.micro` Redis nodes (2 nodes)

Scale up by modifying variables in `terraform.tfvars` as needed.

## Teardown

### Step 1: Remove PostgreSQL Deletion Protection

PostgreSQL clusters have deletion protection enabled by default. Remove it before destroying:

```bash
cd infrastructure/stacks/platform-eks/
terraform apply -auto-approve -var="postgres_deletion_protection=false" -target=module.postgres_aurora.aws_rds_cluster.postgres
```

### Step 2: Clean Up Load Balancers (If Applicable)

If you deployed applications with ingress resources, manually delete any AWS Load Balancers created by the AWS Load Balancer Controller before destroying the VPC:

```bash
# List and delete any ALBs/NLBs created by Kubernetes ingress
kubectl get ingress --all-namespaces
kubectl delete ingress <ingress-name> -n <namespace>

# Or check AWS Console for Load Balancers and delete manually
```

### Step 3: Destroy Infrastructure

```bash
# Destroy platform stack
cd infrastructure/stacks/platform-eks/
terraform destroy

# Destroy foundation stack (if deployed)
cd ../foundation/
terraform destroy
```

## Troubleshooting

### EKS Access Issues
- Ensure your IAM role is in `additional_admin_role_arns`
- Verify EKS access configuration matches one of the valid patterns above
- Check AWS credentials: `aws sts get-caller-identity`

### Kubernetes Resources Not Deploying
- Verify conditional access configuration
- Check that EKS cluster is accessible from your deployment environment

### Terraform Destroy Failures
- **PostgreSQL**: Ensure deletion protection is disabled (see teardown steps)
- **Load Balancers**: Remove any ingress-created load balancers first
- **VPC Dependencies**: Check for remaining ENIs, security groups, or other VPC resources

## Next Steps

After successful deployment:
1. Configure `kubectl`: `aws eks update-kubeconfig --region us-west-2 --name CLUSTER-NAME`
2. Verify access: `kubectl get nodes`
3. Deploy applications using the local stack for K8s resources
