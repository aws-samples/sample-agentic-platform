terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 3
  special = false
  upper   = false
}

# Get current region and account
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Local values
locals {
  name_prefix = var.stack_name != "" ? "${var.stack_name}-" : ""
  suffix      = random_string.suffix.result
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.name

  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Suffix      = local.suffix
    Project     = "Agent Backed WebApp"
    Stack       = "agent-backed-webapp"
  }
}

########################################################
# 1. Cognito — User Authentication
########################################################

module "cognito" {
  source = "../../modules/cognito"

  name_prefix = local.name_prefix
  common_tags = local.common_tags
  environment = var.environment
  domain_name = var.domain_name
  use_custom_domain = var.use_custom_domain
}

########################################################
# 2. S3 — Frontend Static Assets (Private)
########################################################

module "s3_frontend" {
  source = "../../modules/s3"

  common_tags                = local.common_tags
  force_destroy              = true
  bucket_type                = "Frontend"
  enable_cloudfront_oac_policy = true
  cloudfront_distribution_arn  = module.cloudfront.cloudfront_distribution_arn
}

########################################################
# 3. Lambda — API Backend with AgentCore Permissions
########################################################

# Placeholder ZIP for initial deployment
data "archive_file" "placeholder" {
  count       = var.lambda_filename == null && var.lambda_s3_bucket == null ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/placeholder.zip"

  source {
    content  = <<-EOF
      def handler(event, context):
          return {
              "statusCode": 200,
              "headers": {"Content-Type": "application/json"},
              "body": "{\"message\": \"Agent backend placeholder — deploy your code here\"}"
          }
    EOF
    filename = "index.py"
  }
}

module "lambda_agent_backend" {
  source = "../../modules/lambda"

  name_prefix  = local.name_prefix
  function_name = "agent-backend"
  description   = "Backend Lambda for agent-backed webapp — invokes AgentCore Runtime"
  common_tags   = local.common_tags

  runtime     = var.lambda_runtime
  handler     = var.lambda_handler
  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  # Use provided deployment package, or fall back to placeholder
  filename         = var.lambda_filename != null ? var.lambda_filename : (var.lambda_s3_bucket == null ? data.archive_file.placeholder[0].output_path : null)
  source_code_hash = var.lambda_source_code_hash != null ? var.lambda_source_code_hash : (var.lambda_s3_bucket == null ? data.archive_file.placeholder[0].output_base64sha256 : null)
  s3_bucket        = var.lambda_s3_bucket
  s3_key           = var.lambda_s3_key

  environment_variables = {
    COGNITO_USER_POOL_ID = module.cognito.user_pool_id
    COGNITO_CLIENT_ID    = module.cognito.web_client_id
    AWS_ACCOUNT_ID       = local.account_id
  }

  # Inline policy for AgentCore Runtime access
  inline_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AgentCoreRuntimeAccess"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeAgent",
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate"
        ]
        Resource = "*"
      }
    ]
  })
}

########################################################
# 4. API Gateway — HTTP API with Cognito Auth
########################################################

module "api_gateway" {
  source = "../../modules/api-gateway"

  name_prefix = local.name_prefix
  api_name    = "agent-api"
  description = "HTTP API for agent-backed webapp"
  common_tags = local.common_tags

  cognito_user_pool_endpoint = module.cognito.user_pool_endpoint
  cognito_client_id          = module.cognito.web_client_id

  cors_allow_origins = ["*"]

  routes = {
    "POST /api/invoke" = {
      lambda_invoke_arn    = module.lambda_agent_backend.invoke_arn
      lambda_function_name = module.lambda_agent_backend.function_name
      auth_required        = true
    }
    "GET /api/health" = {
      lambda_invoke_arn    = module.lambda_agent_backend.invoke_arn
      lambda_function_name = module.lambda_agent_backend.function_name
      auth_required        = false
    }
  }
}

########################################################
# 5. CloudFront — Distribution (S3 + API Gateway)
########################################################

module "cloudfront" {
  source = "../../modules/cloudfront"

  name_prefix                    = local.name_prefix
  suffix                         = local.suffix
  common_tags                    = local.common_tags
  environment                    = var.environment
  s3_bucket_name                 = module.s3_frontend.bucket_name
  s3_bucket_regional_domain_name = module.s3_frontend.bucket_regional_domain_name
}
