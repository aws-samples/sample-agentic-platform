# Infrastructure Guide for AI Agents

This document provides context for AI agents making infrastructure changes.

## Critical Rules

**ALWAYS run these after ANY infrastructure change:**

```bash
# 1. Security scan for Terraform
cd infrastructure/stacks/<stack-name>/
checkov -d .

# 2. Secret detection (run from repo root after every commit)
cd /path/to/repo
gitleaks detect .
```

Fix any issues before pushing.

## Architecture Overview

The infrastructure uses a **modular Terraform architecture**:

```
Modules (reusable components)
    ↓
Stacks (compose modules for specific purposes)
    ↓
Deployed Infrastructure
```

### Two Platform Options

1. **EKS Platform** (`platform-eks`): Self-managed Kubernetes on EKS
2. **AgentCore Platform** (`platform-agentcore`): Managed Bedrock AgentCore with ECS for extras (LLM Gateway, etc.)

Both platforms provide what's needed to run agents at scale.

## Directory Structure

```
infrastructure/
├── modules/                    # Reusable Terraform components
│   ├── networking/             # VPC, subnets, NAT gateways
│   ├── eks/                    # EKS cluster
│   ├── ecs/                    # ECS cluster (for AgentCore)
│   ├── postgres-aurora/        # Aurora PostgreSQL
│   ├── elasticache/            # Redis
│   ├── cognito/                # Authentication
│   ├── irsa/                   # IAM Roles for Service Accounts
│   ├── kubernetes/             # K8s add-ons
│   ├── knowledgebase/          # Bedrock Knowledge Base
│   ├── agentcore/              # Bedrock AgentCore config
│   ├── cloudfront/             # CDN
│   ├── bastion/                # VPC access
│   ├── kms/                    # Encryption keys
│   ├── s3/                     # S3 buckets
│   ├── litellm/                # LLM Gateway secrets
│   └── ...
│
└── stacks/                     # Deployment stacks
    ├── foundation/             # Base layer: VPC, networking
    ├── platform-eks/           # Platform layer: EKS option
    ├── platform-agentcore/     # Platform layer: AgentCore option
    ├── knowledge-layer/        # Add-on: Bedrock Knowledge Base
    └── agentcore-runtime/      # Add-on: Deploy agents to AgentCore
```

## Stack Hierarchy

### Layer 1: Foundation (Optional)

**Stack:** `foundation/`

Creates base networking if no existing VPC:
- VPC with public/private subnets
- NAT gateways
- KMS encryption keys
- VPC flow logs

```bash
cd infrastructure/stacks/foundation/
terraform init && terraform apply
checkov -d .
```

### Layer 2: Platform (Choose One)

#### Option A: EKS Platform

**Stack:** `platform-eks/`

Full Kubernetes platform for self-managed agents:
- EKS cluster with managed node groups
- Aurora PostgreSQL (with pgvector)
- ElastiCache Redis
- Cognito authentication
- IRSA roles for pod permissions
- Kubernetes add-ons (ALB Controller, External Secrets, OTEL)
- Bastion host
- CloudFront distribution

```bash
cd infrastructure/stacks/platform-eks/
terraform init && terraform apply
checkov -d .
```

#### Option B: AgentCore Platform

**Stack:** `platform-agentcore/`

Managed Bedrock AgentCore with ECS for supporting services:
- Bedrock AgentCore for agent runtime
- ECS cluster for LLM Gateway and other services
- Aurora PostgreSQL
- ElastiCache Redis
- Cognito authentication
- CloudFront distribution

```bash
cd infrastructure/stacks/platform-agentcore/
terraform init && terraform apply
checkov -d .
```

### Layer 3: Add-ons (Plug and Play)

These stacks add capabilities to either platform:

#### Knowledge Layer

**Stack:** `knowledge-layer/`

Adds RAG capabilities:
- S3 bucket for documents
- OpenSearch Serverless collection
- Bedrock Knowledge Base
- Data source configuration

```bash
cd infrastructure/stacks/knowledge-layer/
terraform init && terraform apply
checkov -d .
```

#### AgentCore Runtime

**Stack:** `agentcore-runtime/`

Deploys individual agents to AgentCore:
- Agent configurations
- Memory stores
- Per-agent IAM roles

```bash
cd infrastructure/stacks/agentcore-runtime/
terraform apply -var-file="agentic_chat.tfvars"
checkov -d .
```

## Modules Reference

Modules are reusable components composed by stacks. Key modules:

| Module | Purpose | Used By |
|--------|---------|---------|
| `networking` | VPC, subnets, NAT | foundation |
| `eks` | EKS cluster | platform-eks |
| `ecs` | ECS cluster | platform-agentcore |
| `postgres-aurora` | Aurora PostgreSQL | platform-eks, platform-agentcore |
| `elasticache` | Redis cluster | platform-eks, platform-agentcore |
| `cognito` | User authentication | platform-eks, platform-agentcore |
| `irsa` | K8s service account IAM | platform-eks |
| `kubernetes` | K8s add-ons | platform-eks |
| `knowledgebase` | Bedrock KB | knowledge-layer |
| `agentcore` | AgentCore config | platform-agentcore |
| `cloudfront` | CDN distribution | platform-eks, platform-agentcore |
| `bastion` | VPC access host | platform-eks |
| `kms` | Encryption keys | foundation |
| `s3` | S3 buckets | various |
| `litellm` | LLM Gateway secrets | platform-eks, platform-agentcore |

## Making Changes

### Adding a New Module

1. Create directory: `infrastructure/modules/my-module/`
2. Add files:
   - `main.tf` - Resources
   - `variables.tf` - Input variables
   - `outputs.tf` - Output values
3. Run Checkov: `checkov -d infrastructure/modules/my-module/`

### Modifying a Stack

1. Navigate to stack: `cd infrastructure/stacks/<stack>/`
2. Make changes to `.tf` files
3. Plan: `terraform plan`
4. **Run Checkov**: `checkov -d .`
5. Apply: `terraform apply`

### Adding a Module to a Stack

```hcl
# In stack's main.tf
module "my_module" {
  source = "../../modules/my-module"
  
  # Pass required variables
  name_prefix = local.name_prefix
  vpc_id      = module.networking.vpc_id
  common_tags = local.common_tags
}
```

## Security Requirements

### Always Run Security Scans

```bash
# After ANY infrastructure change
checkov -d .

# After EVERY commit (from repo root)
gitleaks detect .

# Skip specific Checkov check (with justification)
checkov -d . --skip-check CKV_AWS_123

# Suppress in code (document reason)
resource "aws_s3_bucket" "example" {
  # checkov:skip=CKV_AWS_18:Logging handled by centralized logging
  bucket = "example"
}
```

### Required Security Patterns

1. **Encryption**: All data encrypted at rest (KMS) and in transit (TLS)
2. **Private Networks**: Workloads in private subnets only
3. **Least Privilege**: Minimal IAM permissions via IRSA
4. **No Secrets in Code**: Use Secrets Manager + External Secrets
5. **Deletion Protection**: Enable for databases and critical resources

### EKS Access Configuration

Only these combinations are valid:

```hcl
# Production (private cluster)
enable_eks_public_access = false
deploy_inside_vpc = true

# Testing only (public cluster)
enable_eks_public_access = true
deploy_inside_vpc = false
```

## Common Operations

### Deploy Full Platform (EKS)

```bash
# 1. Foundation (if no existing VPC)
cd infrastructure/stacks/foundation/
terraform init && terraform apply
checkov -d .

# 2. Platform
cd ../platform-eks/
terraform init && terraform apply
checkov -d .

# 3. Knowledge layer (optional)
cd ../knowledge-layer/
terraform init && terraform apply
checkov -d .
```

### Deploy Full Platform (AgentCore)

```bash
# 1. Foundation (if no existing VPC)
cd infrastructure/stacks/foundation/
terraform init && terraform apply
checkov -d .

# 2. Platform
cd ../platform-agentcore/
terraform init && terraform apply
checkov -d .

# 3. Deploy agents
cd ../agentcore-runtime/
terraform apply -var-file="agentic_chat.tfvars"
checkov -d .
```

### Destroy Infrastructure

```bash
# Remove deletion protection first
terraform apply -var="postgres_deletion_protection=false" \
  -target=module.postgres_aurora.aws_rds_cluster.postgres

# Destroy in reverse order
cd infrastructure/stacks/knowledge-layer/
terraform destroy

cd ../platform-eks/  # or platform-agentcore
terraform destroy

cd ../foundation/
terraform destroy
```

## Troubleshooting

### Checkov Failures

Fix security issues or suppress with documented justification:

```hcl
# checkov:skip=CKV_AWS_XXX:Reason for skipping
```

### State Lock

```bash
aws dynamodb delete-item \
  --table-name terraform-state-lock \
  --key '{"LockID": {"S": "lock-id"}}'
```

### EKS Access

```bash
aws eks update-kubeconfig --region us-west-2 --name CLUSTER-NAME
kubectl get nodes
```

### Database Access

```bash
# Port forward through bastion
aws ssm start-session \
  --target BASTION-INSTANCE-ID \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "portNumber=5432,localPortNumber=5432,host=AURORA-ENDPOINT"
```

## Key Files

| File | Purpose |
|------|---------|
| `main.tf` | Primary resources and module calls |
| `variables.tf` | Input variable definitions |
| `outputs.tf` | Output value definitions |
| `backend.tf` | Terraform state configuration |
| `terraform.tfvars` | Variable values (don't commit secrets) |
| `*.tfvars.example` | Example variable files |
