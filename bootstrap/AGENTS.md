# Bootstrap Guide for AI Agents

This document provides context for AI agents modifying bootstrap templates and scripts.

## Critical Rules

**After ANY change to CloudFormation templates:**

```bash
# Validate template syntax
aws cloudformation validate-template --template-body file://template.yaml

# Run cfn-lint if available
cfn-lint template.yaml
```

**After EVERY commit:**

```bash
gitleaks detect .
```

**Never commit:**
- AWS account IDs
- IAM role ARNs with real account IDs
- Any credentials or secrets

## Overview

Bootstrap templates automate the initial deployment of the Agentic Platform. They create:

1. **Terraform state management** (S3 bucket)
2. **CI/CD pipeline** (CodeBuild)
3. **VPC and networking** (for secure deployment)
4. **IAM roles** (for deployment permissions)

## Directory Structure

```
bootstrap/
├── infra-bootstrap.yaml           # EKS platform bootstrap (main)
├── agentcore-platform-bootstrap.yaml  # AgentCore platform bootstrap
├── agentptfm-cicd-role.yaml       # Sample CI/CD IAM role
├── agentptfm-federated-role.yaml  # Sample federated IAM role
├── github-bootstrap.yaml          # GitHub Actions OIDC setup
├── langfuse-bootstrap.sh          # Langfuse observability setup
├── README.md                      # Main documentation
├── AGENTCORE_BOOTSTRAP_README.md  # AgentCore-specific docs
└── codebuild-manual-destroy-changes.md  # Teardown instructions
```

## Bootstrap Options

### Option 1: EKS Platform (`infra-bootstrap.yaml`)

Full Kubernetes platform on EKS:

```bash
aws cloudformation create-stack \
  --stack-name agentptfm-bootstrap \
  --template-body file://infra-bootstrap.yaml \
  --parameters \
    ParameterKey=FederatedRoleName,ParameterValue=<ROLE_NAME> \
    ParameterKey=CICDRoleName,ParameterValue=<CICD_ROLE_NAME> \
  --capabilities CAPABILITY_NAMED_IAM
```

**Creates:**
- VPC with public/private subnets
- S3 bucket for Terraform state
- CodeBuild project for Terraform deployment
- Lambda custom resource for lifecycle management
- Optional KMS key

### Option 2: AgentCore Platform (`agentcore-platform-bootstrap.yaml`)

Managed Bedrock AgentCore platform:

```bash
aws cloudformation create-stack \
  --stack-name agentptfm-bootstrap \
  --template-body file://agentcore-platform-bootstrap.yaml \
  --parameters \
    ParameterKey=CICDRoleName,ParameterValue=<CICD_ROLE_NAME> \
    ParameterKey=PlatformAdminRoleName,ParameterValue=<ADMIN_ROLE_NAME> \
  --capabilities CAPABILITY_NAMED_IAM
```

**Creates:**
- S3 bucket for Terraform state
- CodeBuild project for Terraform deployment
- Lambda custom resource for lifecycle management

## Template Files

### infra-bootstrap.yaml

Main EKS platform bootstrap. Key parameters:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `RepoUrl` | Git repo URL | `https://github.com/aws-samples/sample-agentic-platform` |
| `RepoBranchName` | Branch to deploy | `main` |
| `TerraformPath` | Path to Terraform | `sample-agentic-platform/infrastructure/stacks/platform-eks` |
| `FederatedRoleName` | Role for EKS access | Required |
| `CICDRoleName` | Role for CodeBuild | Required |
| `UseKMS` | Enable KMS encryption | `false` |
| `StackName` | Resource name prefix | `agentic-platform` |
| `Environment` | Environment name | `dev` |

Key resources:
- `VPC`, `PublicSubnet*`, `PrivateSubnet*` - Networking
- `TerraformStateBucket` - S3 for Terraform state
- `CodeBuildProject` - Runs Terraform
- `TerraformDeploymentLambda` - Custom resource handler

### agentcore-platform-bootstrap.yaml

AgentCore platform bootstrap. Key parameters:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `CICDRoleName` | Role for CodeBuild | Required |
| `PlatformAdminRoleName` | Admin role for platform | Required |
| `RepoUrl` | Git repo URL | Default repo |
| `TerraformPath` | Path to Terraform | `platform-agentcore` stack |

### agentptfm-cicd-role.yaml

Sample IAM role for CI/CD. Creates role with:
- Trust relationship with `codebuild.amazonaws.com`
- Permissions for infrastructure deployment

**Security Note:** Review and restrict permissions before use.

### agentptfm-federated-role.yaml

Sample IAM role for EKS access. Creates role with:
- Permissions for EKS cluster administration
- KMS key access (if enabled)

**Security Note:** Review and restrict permissions before use.

### github-bootstrap.yaml

GitHub Actions OIDC setup. Key parameters:

| Parameter | Description |
|-----------|-------------|
| `GitHubOrg` | GitHub organization or username |
| `GitHubRepo` | Repository name |

Creates:
- OIDC provider for GitHub
- IAM role for GitHub Actions
- ECR push permissions

## Modifying Templates

### Adding a Parameter

```yaml
Parameters:
  NewParameter:
    Type: String
    Description: Description of the parameter
    Default: "default-value"
    AllowedValues:
      - "option1"
      - "option2"
```

### Adding a Resource

```yaml
Resources:
  NewResource:
    Type: AWS::Service::Resource
    Properties:
      PropertyName: !Ref ParameterName
      Tags:
        - Key: Name
          Value: !Sub "${StackName}-resource-name"
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: CloudFormation
        - Key: Project
          Value: "Agentic Platform Sample"
```

### Adding an Output

```yaml
Outputs:
  NewOutput:
    Description: Description of the output
    Value: !Ref NewResource
    Export:
      Name: !Sub "${AWS::StackName}-NewOutput"
```

### Using Conditions

```yaml
Conditions:
  CreateResource: !Equals 
    - !Ref SomeParameter
    - "true"

Resources:
  ConditionalResource:
    Type: AWS::Service::Resource
    Condition: CreateResource
    Properties:
      # ...
```

## Validation

### Validate Template Syntax

```bash
# AWS CLI validation
aws cloudformation validate-template \
  --template-body file://template.yaml

# cfn-lint (more thorough)
pip install cfn-lint
cfn-lint template.yaml
```

### Test Deployment

```bash
# Create stack with --dry-run equivalent
aws cloudformation create-change-set \
  --stack-name test-stack \
  --template-body file://template.yaml \
  --change-set-name test-changes \
  --parameters ParameterKey=Key,ParameterValue=Value \
  --capabilities CAPABILITY_NAMED_IAM

# Review changes
aws cloudformation describe-change-set \
  --stack-name test-stack \
  --change-set-name test-changes

# Delete change set (don't execute)
aws cloudformation delete-change-set \
  --stack-name test-stack \
  --change-set-name test-changes
```

## Common Patterns

### Tagging Convention

All resources should have these tags:

```yaml
Tags:
  - Key: Name
    Value: !Sub "${StackName}-resource-name"
  - Key: Environment
    Value: !Ref Environment
  - Key: ManagedBy
    Value: CloudFormation
  - Key: Project
    Value: "Agentic Platform Sample"
```

### Cross-Stack References

Export values:
```yaml
Outputs:
  VpcId:
    Value: !Ref VPC
    Export:
      Name: !Sub "${AWS::StackName}-VpcId"
```

Import in another stack:
```yaml
Resources:
  Resource:
    Properties:
      VpcId: !ImportValue "stack-name-VpcId"
```

### IAM Role Trust Relationships

For CodeBuild:
```yaml
AssumeRolePolicyDocument:
  Version: "2012-10-17"
  Statement:
    - Effect: Allow
      Principal:
        Service: codebuild.amazonaws.com
      Action: sts:AssumeRole
```

For Lambda:
```yaml
AssumeRolePolicyDocument:
  Version: "2012-10-17"
  Statement:
    - Effect: Allow
      Principal:
        Service: lambda.amazonaws.com
      Action: sts:AssumeRole
```

## Deployment Order

1. **IAM Roles** (if using sample templates):
   ```bash
   aws cloudformation create-stack --stack-name agentptfm-cicd-role \
     --template-body file://agentptfm-cicd-role.yaml \
     --capabilities CAPABILITY_NAMED_IAM
   
   aws cloudformation create-stack --stack-name agentptfm-federated-role \
     --template-body file://agentptfm-federated-role.yaml \
     --capabilities CAPABILITY_NAMED_IAM
   ```

2. **Infrastructure Bootstrap**:
   ```bash
   aws cloudformation create-stack --stack-name agentptfm-bootstrap \
     --template-body file://infra-bootstrap.yaml \
     --parameters ... \
     --capabilities CAPABILITY_NAMED_IAM
   ```

3. **GitHub Bootstrap** (optional):
   ```bash
   aws cloudformation create-stack --stack-name github-bootstrap \
     --template-body file://github-bootstrap.yaml \
     --parameters ... \
     --capabilities CAPABILITY_NAMED_IAM
   ```

## Teardown

Reverse order of deployment:

```bash
# 1. Delete GitHub bootstrap
aws cloudformation delete-stack --stack-name github-bootstrap

# 2. Delete infrastructure bootstrap (triggers Terraform destroy)
aws cloudformation delete-stack --stack-name agentptfm-bootstrap

# 3. Delete IAM roles
aws cloudformation delete-stack --stack-name agentptfm-federated-role
aws cloudformation delete-stack --stack-name agentptfm-cicd-role
```

**Note:** The infrastructure bootstrap deletion triggers Terraform destroy via the custom resource Lambda.

## Troubleshooting

### Stack Creation Failed

```bash
# Check events
aws cloudformation describe-stack-events \
  --stack-name stack-name \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

### CodeBuild Failed

```bash
# Check CodeBuild logs
aws logs get-log-events \
  --log-group-name /aws/codebuild/project-name \
  --log-stream-name stream-name
```

### Lambda Custom Resource Failed

Check CloudWatch Logs for the Lambda function:
```bash
aws logs describe-log-streams \
  --log-group-name /aws/lambda/function-name

aws logs get-log-events \
  --log-group-name /aws/lambda/function-name \
  --log-stream-name stream-name
```

## Security Considerations

1. **Review IAM roles** before deploying sample role templates
2. **Use least privilege** - restrict permissions to what's needed
3. **Enable KMS** for sensitive environments (`UseKMS=true`)
4. **Private subnets** - workloads run in private subnets only
5. **No public IPs** - `MapPublicIpOnLaunch: false` on all subnets
6. **Secrets** - never hardcode credentials in templates
