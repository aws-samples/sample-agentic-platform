# Agent Deployment Infrastructure

This Terraform configuration deploys individual agents to AWS using Amazon Bedrock AgentCore. It creates the necessary infrastructure for each agent including ECR repositories, container builds, and Agent Core runtimes.

## Architecture

- **ECR Repository**: Stores Docker images for each agent
- **Agent Core Runtime**: Bedrock Agent Core runtime instance
- **Agent Core Endpoint**: Optional endpoint for external access
- **Docker Build**: Automated container build and push process

## Agent Core Module

The `agentcore` module is based on the [AWS IA Terraform AgentCore module](https://github.com/aws-ia/terraform-aws-agentcore/tree/main) with bug fixes for prefix validation. The original module fails when random prefixes start with numbers, violating AgentCore regex rules.

## Setup

### 1. Create Agent Configuration Files

Copy the example files and customize for each agent:

```bash
# Create config files from examples
cp agent.tfvars.example agentic_chat.tfvars
cp agent.tfvars.example langgraph_chat.tfvars
cp agent.tfvars.example strands_glue_athena.tfvars

# Edit as needed
vim agentic-chat.tfvars
```

Your tfvars file should look something like this:
```
########################################################
# Core Configuration
########################################################

agent_name        = "name of the directory under src/agentic_platform/agent/"
agent_description = "useful description of the agent"

# Pass environment variables as neeeded.
environment_variables = {
    "ENVIRONMENT": "local",
    "LITELLM_API_ENDPOINT": "<cloudfront url from the agentcore platform stack>/api/litellm"
    "LITELLM_KEY": "<key from the litellm secret deployed in the agentcore platform stack>
}
```

To invoke to an LLM, you will need the litellm endpoint and key. Currently there's no other way to pass secrets into an agentcore runtime besides pulling the secret at the start of every invocation.

### 2. Configure Backend

Ensure your `backend.tf` or `providers.tf` has S3 backend configured:

```hcl
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "agentcore-agent/terraform.tfstate"
    region = "us-east-1"
  }
}
```

## Deployment

### Using Terraform Workspaces

Each agent uses a separate workspace for isolated state management:

```bash
# Deploy agentic-chat agent
terraform workspace select agentic_chat || terraform workspace new agentic_chat
terraform plan -var-file="agentic_chat.tfvars"
terraform apply -var-file="agentic_chat.tfvars"

# Deploy langgraph-chat agent  
terraform workspace select langgraph_chat || terraform workspace new langgraph_chat
terraform apply -var-file="langgraph_chat.tfvars"

# Deploy strands-glue-athena agent
terraform workspace select strands_glue_athena || terraform workspace new strands_glue_athena
terraform apply -var-file="strands_glue_athena.tfvars"
```

### State Management

Workspaces automatically create separate S3 keys in the same bucket:
- `agentcore-agent/env:/agentic-chat/terraform.tfstate`
- `agentcore-agent/env:/langgraph-chat/terraform.tfstate`
- `agentcore-agent/env:/strands-glue-athena/terraform.tfstate`

## Configuration Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `agent_name` | Name of the agent (used for ECR repo and runtime) | Yes |
| `agent_description` | Description of the agent | Yes |
| `create_endpoint` | Whether to create Agent Core endpoint | No (default: true) |
| `network_mode` | Network mode for runtime | No (default: "VPC") |
| `environment_variables` | Environment variables for runtime | No |
| `authorizer_configuration` | Authorizer config for endpoint | No |

## Example Configuration

```hcl
# agentic-chat.tfvars
agent_name        = "agentic-chat"
agent_description = "AgentCore runtime for agentic-chat"

environment_variables = {
  LOG_LEVEL = "INFO"
  ENV       = "production"
}
```

## Outputs

- `runtime_arn`: ARN of the created Agent Core runtime
- `runtime_endpoint_arn`: ARN of the created runtime endpoint
- `ecr_repository_url`: URL of the ECR repository
- `ecr_repository_name`: Name of the ECR repository
