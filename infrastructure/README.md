# Infrastructure Guide

This guide explains the infrastructure architecture, modules, stacks, and deployment workflows for the Agentic Platform.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Directory Structure](#directory-structure)
- [Terraform Modules](#terraform-modules)
- [Deployment Stacks](#deployment-stacks)
- [Deployment Workflow](#deployment-workflow)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)

## Architecture Overview

The infrastructure uses Terraform to deploy a complete agentic platform on AWS with:

- **EKS Cluster**: Kubernetes for containerized workloads
- **Aurora PostgreSQL**: Primary database with pgvector extension
- **ElastiCache Redis**: Caching layer
- **Cognito**: Authentication and authorization
- **CloudFront**: CDN and API gateway
- **Bedrock Knowledge Base**: RAG capabilities
- **OpenTelemetry**: Observability stack

### Key Principles

1. **Modular Design**: Reusable Terraform modules for each component
2. **Stack-Based Deployment**: Logical grouping of infrastructure
3. **Security First**: Private EKS, encryption at rest, least privilege IAM
4. **Observable**: Built-in telemetry and monitoring
5. **Cost Optimized**: Minimal defaults, scale as needed

## Directory Structure

```
infrastructure/
├── modules/                    # Reusable Terraform modules
│   ├── agentcore/              # Bedrock AgentCore integration
│   ├── agentcore-memory/       # AgentCore memory configuration
│   ├── bastion/                # Bastion host for VPC access
│   ├── cloudfront/             # CloudFront distribution
│   ├── cognito/                # Cognito user pools and identity
│   ├── ecs/                    # ECS cluster and services
│   ├── eks/                    # EKS cluster configuration
│   ├── elasticache/            # Redis cluster
│   ├── irsa/                   # IAM Roles for Service Accounts
│   ├── k8s-configmap/          # Kubernetes ConfigMaps
│   ├── kms/                    # KMS encryption keys
│   ├── knowledgebase/          # Bedrock Knowledge Base
│   ├── kubernetes/             # Kubernetes add-ons
│   ├── litellm/                # LiteLLM gateway secrets
│   ├── networking/             # VPC, subnets, NAT gateways
│   ├── parameter-store/        # SSM Parameter Store
│   ├── postgres-admin-setup/   # PostgreSQL admin configuration
│   ├── postgres-aurora/        # Aurora PostgreSQL cluster
│   └── s3/                     # S3 buckets
│
└── stacks/                     # Deployment stacks
    ├── foundation/             # VPC and networking (optional)
    ├── platform-eks/           # Core platform (EKS, Aurora, Redis)
    ├── platform-agentcore/     # Bedrock AgentCore platform
    ├── agentcore-runtime/      # AgentCore agent deployments
    └── knowledge-layer/        # Bedrock Knowledge Base
```

## Terraform Modules

### Core Infrastructure Modules

#### networking
Creates VPC, subnets, NAT gateways, and flow logs.

**Key Resources:**
- VPC with public/private subnets across 2 AZs
- NAT gateways for private subnet internet access
- VPC flow logs to CloudWatch

**Usage:**
```hcl
module "networking" {
  source = "../../modules/networking"
  
  name_prefix           = "platform"
  suffix               = "abc"
  common_tags          = local.common_tags
  enable_kms_encryption = true
  kms_key_arn          = module.kms.kms_key_arn
}
```

#### eks
Deploys EKS cluster with managed node groups.

**Key Resources:**
- EKS cluster with OIDC provider
- Managed node groups with auto-scaling
- Cluster and node IAM roles
- Security groups
- EKS add-ons (CoreDNS, kube-proxy, VPC CNI, EBS CSI)

**Usage:**
```hcl
module "eks" {
  source = "../../modules/eks"
  
  cluster_name           = "platform-eks"
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnet_ids
  enable_public_access  = false
  additional_admin_role_arns = var.additional_admin_role_arns
}
```

#### postgres-aurora
Creates Aurora PostgreSQL cluster with pgvector extension.

**Key Resources:**
- Aurora PostgreSQL cluster (2 instances)
- DB subnet group
- Security groups
- Secrets Manager for credentials
- IAM authentication support

**Usage:**
```hcl
module "postgres_aurora" {
  source = "../../modules/postgres-aurora"
  
  cluster_identifier = "platform-postgres"
  vpc_id            = module.networking.vpc_id
  subnet_ids        = module.networking.private_subnet_ids
  instance_class    = "db.t4g.medium"
  instance_count    = 2
}
```

#### elasticache
Deploys Redis cluster for caching.

**Key Resources:**
- ElastiCache Redis cluster
- Subnet group
- Security groups
- Secrets Manager for connection details

**Usage:**
```hcl
module "elasticache" {
  source = "../../modules/elasticache"
  
  cluster_id         = "platform-redis"
  vpc_id            = module.networking.vpc_id
  subnet_ids        = module.networking.private_subnet_ids
  node_type         = "cache.t4g.micro"
  num_cache_nodes   = 2
}
```

#### cognito
Sets up Cognito for authentication.

**Key Resources:**
- User pool with email/password auth
- User pool clients (web, mobile, M2M)
- Identity pool for AWS credentials
- User groups (admins, users)
- Resource server with scopes

**Usage:**
```hcl
module "cognito" {
  source = "../../modules/cognito"
  
  user_pool_name = "platform-users"
  common_tags    = local.common_tags
}
```

#### irsa
Creates IAM Roles for Service Accounts (IRSA).

**Key Resources:**
- Service account IAM roles for:
  - LiteLLM gateway (Bedrock access)
  - Memory gateway (RDS/Secrets access)
  - Retrieval gateway (OpenSearch/Bedrock KB access)
  - Agents (Bedrock/S3 access)
  - AWS Load Balancer Controller
  - EBS CSI Driver
  - External Secrets Operator
  - OTEL Collector

**Usage:**
```hcl
module "irsa" {
  source = "../../modules/irsa"
  
  cluster_name          = module.eks.cluster_name
  oidc_provider_arn     = module.eks.oidc_provider_arn
  oidc_provider_url     = module.eks.oidc_provider_url
  namespace             = "default"
}
```

#### knowledgebase
Deploys Bedrock Knowledge Base for RAG.

**Key Resources:**
- S3 bucket for documents
- OpenSearch Serverless collection
- Bedrock Knowledge Base
- Data source configuration
- IAM roles and policies

**Usage:**
```hcl
module "knowledgebase" {
  source = "../../modules/knowledgebase"
  
  knowledge_base_name = "platform-kb"
  embedding_model_arn = "arn:aws:bedrock:us-west-2::foundation-model/amazon.titan-embed-text-v1"
  common_tags         = local.common_tags
}
```

### Kubernetes Modules

#### kubernetes
Deploys Kubernetes add-ons and configurations.

**Key Resources:**
- AWS Load Balancer Controller
- External Secrets Operator
- OpenTelemetry Collectors
- Storage classes
- ConfigMaps

**Usage:**
```hcl
module "kubernetes" {
  source = "../../modules/kubernetes"
  
  cluster_name                    = module.eks.cluster_name
  load_balancer_controller_role_arn = module.irsa.load_balancer_controller_role_arn
  external_secrets_role_arn       = module.irsa.external_secrets_role_arn
  otel_collector_role_arn         = module.irsa.otel_collector_role_arn
}
```

## Deployment Stacks

### foundation
Optional stack for creating VPC and networking from scratch.

**Components:**
- VPC with public/private subnets
- NAT gateways
- KMS encryption keys
- VPC flow logs

**When to Use:**
- New AWS account with no existing VPC
- Isolated environment for testing

**Deployment:**
```bash
cd infrastructure/stacks/foundation/
terraform init
terraform plan
terraform apply
```

### platform-eks
Core platform stack with EKS, databases, and supporting services.

**Components:**
- EKS cluster with managed node groups
- Aurora PostgreSQL cluster
- ElastiCache Redis cluster
- Cognito authentication
- Bastion host
- CloudFront distribution
- IRSA roles
- Kubernetes add-ons

**Prerequisites:**
- VPC and subnets (from foundation or existing)
- S3 bucket for Terraform state

**Deployment:**
```bash
cd infrastructure/stacks/platform-eks/

# Create backend.tf
cat > backend.tf << EOF
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "platform-eks/terraform.tfstate"
    region = "us-west-2"
    encrypt = true
  }
}
EOF

# Create terraform.tfvars
cat > terraform.tfvars << EOF
aws_region  = "us-west-2"
environment = "dev"

vpc_id         = "vpc-xxxxx"
vpc_cidr_block = "10.0.0.0/16"
private_subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]
public_subnet_ids  = ["subnet-zzzzz", "subnet-aaaaa"]

enable_eks_public_access = false
deploy_inside_vpc = true

additional_admin_role_arns = [
  "arn:aws:iam::ACCOUNT-ID:role/YourAdminRole"
]
EOF

# Deploy
terraform init
terraform plan
terraform apply

# Run security scan
checkov -d .
```

### knowledge-layer
Deploys Bedrock Knowledge Base for RAG capabilities.

**Components:**
- S3 bucket for documents
- OpenSearch Serverless collection
- Bedrock Knowledge Base
- Data source
- IRSA role for retrieval gateway

**Prerequisites:**
- platform-eks stack deployed
- Documents to upload to S3

**Deployment:**
```bash
cd infrastructure/stacks/knowledge-layer/
terraform init
terraform plan
terraform apply

# Upload documents
aws s3 cp ./documents/ s3://BUCKET-NAME/ --recursive

# Sync knowledge base
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id KB-ID \
  --data-source-id DS-ID

# Run security scan
checkov -d .
```

### platform-agentcore
Alternative platform using Bedrock AgentCore instead of EKS.

**Components:**
- ECS cluster for AgentCore
- Aurora PostgreSQL
- ElastiCache Redis
- Cognito
- CloudFront
- AgentCore configuration

**When to Use:**
- Prefer managed Bedrock AgentCore over self-managed EKS
- Simpler operational model

**Deployment:**
```bash
cd infrastructure/stacks/platform-agentcore/
terraform init
terraform plan
terraform apply

# Run security scan
checkov -d .
```

### agentcore-runtime
Deploys individual agents to Bedrock AgentCore.

**Components:**
- AgentCore agent configuration
- Agent memory stores
- IAM roles

**Prerequisites:**
- platform-agentcore stack deployed

**Deployment:**
```bash
cd infrastructure/stacks/agentcore-runtime/

# Deploy specific agent
terraform apply -var-file="agentic_chat.tfvars"
terraform apply -var-file="agentic_rag.tfvars"

# Run security scan
checkov -d .
```

## Deployment Workflow

### 1. Prerequisites

```bash
# Install tools
brew install terraform awscli checkov

# Configure AWS CLI
aws configure

# Verify access
aws sts get-caller-identity
```

### 2. Create State Bucket

```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://your-terraform-state-bucket --region us-west-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket your-terraform-state-bucket \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket your-terraform-state-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

### 3. Deploy Foundation (Optional)

```bash
cd infrastructure/stacks/foundation/
terraform init
terraform plan
terraform apply

# Run security scan
checkov -d .

# Save outputs
terraform output > foundation-outputs.txt
```

### 4. Deploy Platform

```bash
cd infrastructure/stacks/platform-eks/

# Create backend configuration
cat > backend.tf << EOF
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "platform-eks/terraform.tfstate"
    region = "us-west-2"
    encrypt = true
  }
}
EOF

# Create variables file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Initialize and deploy
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Run security scan
checkov -d .

# Configure kubectl
aws eks update-kubeconfig \
  --region us-west-2 \
  --name $(terraform output -raw cluster_name)

# Verify
kubectl get nodes
```

### 5. Deploy Knowledge Layer (Optional)

```bash
cd infrastructure/stacks/knowledge-layer/
terraform init
terraform plan
terraform apply

# Run security scan
checkov -d .

# Upload documents and sync
aws s3 cp ./docs/ s3://$(terraform output -raw bucket_name)/ --recursive
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id $(terraform output -raw knowledge_base_id) \
  --data-source-id $(terraform output -raw data_source_id)
```

### 6. Deploy Applications

```bash
# Deploy gateway services
./deploy/deploy-gateways.sh --build

# Deploy agents
./deploy/deploy-application.sh agentic-chat agent --build
./deploy/deploy-application.sh agentic-rag agent --build
```

## Security Best Practices

### Always Run Checkov

Run Checkov security scan after every Terraform change:

```bash
# Scan specific stack
cd infrastructure/stacks/platform-eks/
checkov -d .

# Scan all infrastructure
cd infrastructure/
checkov -d .

# Scan with specific frameworks
checkov -d . --framework terraform

# Output to file
checkov -d . -o json > checkov-results.json
```

### Common Security Checks

1. **Encryption at Rest**
   - All databases encrypted with KMS
   - S3 buckets encrypted
   - EBS volumes encrypted

2. **Encryption in Transit**
   - TLS for all API endpoints
   - VPC endpoints for AWS services
   - Private EKS cluster endpoint

3. **Network Security**
   - Private subnets for workloads
   - Security groups with least privilege
   - No public database access

4. **IAM Security**
   - IRSA for pod-level permissions
   - No long-lived credentials
   - Least privilege policies

5. **Secrets Management**
   - Secrets Manager for credentials
   - External Secrets Operator in K8s
   - No secrets in code or logs

### EKS Access Configuration

**Valid Configurations:**

✅ **Secure (Production)**:
```hcl
enable_eks_public_access = false
deploy_inside_vpc = true
```

✅ **Testing Only**:
```hcl
enable_eks_public_access = true
deploy_inside_vpc = false
```

❌ **Invalid**:
- Both true (conflicting)
- Both false (no access)

### Deletion Protection

Enable deletion protection for critical resources:

```hcl
# PostgreSQL
postgres_deletion_protection = true

# S3 buckets
prevent_destroy = true
```

## Troubleshooting

### Terraform State Lock

```bash
# If state is locked
aws dynamodb delete-item \
  --table-name terraform-state-lock \
  --key '{"LockID": {"S": "your-lock-id"}}'
```

### EKS Access Issues

```bash
# Verify IAM role
aws sts get-caller-identity

# Update kubeconfig
aws eks update-kubeconfig \
  --region us-west-2 \
  --name CLUSTER-NAME

# Check access entries
aws eks list-access-entries \
  --cluster-name CLUSTER-NAME

# Describe access entry
aws eks describe-access-entry \
  --cluster-name CLUSTER-NAME \
  --principal-arn YOUR-ROLE-ARN
```

### PostgreSQL Connection Issues

```bash
# Port forward through bastion
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*bastion*" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

aws ssm start-session \
  --target $INSTANCE_ID \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "portNumber=5432,localPortNumber=5432,host=AURORA-ENDPOINT"
```

### Destroy Failures

```bash
# Remove deletion protection
terraform apply -auto-approve \
  -var="postgres_deletion_protection=false" \
  -target=module.postgres_aurora.aws_rds_cluster.postgres

# Delete load balancers created by K8s
kubectl get ingress --all-namespaces
kubectl delete ingress INGRESS-NAME -n NAMESPACE

# Force destroy S3 buckets
aws s3 rm s3://BUCKET-NAME --recursive
terraform destroy -target=module.s3

# Full destroy
terraform destroy
```

### Checkov Failures

```bash
# Skip specific checks
checkov -d . --skip-check CKV_AWS_123

# Suppress in code
resource "aws_s3_bucket" "example" {
  # checkov:skip=CKV_AWS_18:Logging not required for this bucket
  bucket = "example"
}

# Create suppressions file
cat > .checkov.yaml << EOF
skip-check:
  - id: CKV_AWS_123
    comment: "Reason for skipping"
EOF
```

## Cost Optimization

### Default Sizes

The stacks use minimal defaults:

```hcl
# EKS nodes
node_instance_types = ["t3.medium"]
node_desired_size   = 2
node_min_size       = 2
node_max_size       = 4

# Aurora PostgreSQL
postgres_instance_class = "db.t4g.medium"
postgres_instance_count = 2

# ElastiCache Redis
redis_node_type      = "cache.t4g.micro"
redis_num_cache_nodes = 2
```

### Scaling Up

Modify `terraform.tfvars` for production:

```hcl
# EKS nodes
node_instance_types = ["t3.large"]
node_desired_size   = 4
node_min_size       = 4
node_max_size       = 10

# Aurora PostgreSQL
postgres_instance_class = "db.r6g.xlarge"
postgres_instance_count = 3

# ElastiCache Redis
redis_node_type      = "cache.r6g.large"
redis_num_cache_nodes = 3
```

## Additional Resources

- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Checkov Documentation](https://www.checkov.io/)
