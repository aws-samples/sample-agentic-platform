# – Bedrock Agent Core Runtime –
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "random_string" "solution_prefix" {
  length  = 4
  special = false
  upper   = false
  numeric = false
}

locals {
  create_runtime = var.create_runtime
}

resource "awscc_bedrockagentcore_runtime" "agent_runtime" {
  count              = local.create_runtime ? 1 : 0
  agent_runtime_name = "${random_string.solution_prefix.result}_${var.runtime_name}"
  description        = var.runtime_description
  role_arn           = var.runtime_role_arn != null ? var.runtime_role_arn : aws_iam_role.runtime_role[0].arn

  agent_runtime_artifact = {
    container_configuration = {
      container_uri = var.runtime_container_uri
    }
  }

  network_configuration = {
    network_mode = var.runtime_network_mode
  }

  environment_variables = var.runtime_environment_variables

  authorizer_configuration = var.runtime_authorizer_configuration != null ? {
    custom_jwt_authorizer = {
      allowed_audience = var.runtime_authorizer_configuration.custom_jwt_authorizer.allowed_audience
      allowed_clients  = var.runtime_authorizer_configuration.custom_jwt_authorizer.allowed_clients
      discovery_url    = var.runtime_authorizer_configuration.custom_jwt_authorizer.discovery_url
    }
  } : null

  protocol_configuration = var.runtime_protocol_configuration
  tags                   = var.runtime_tags

  depends_on = [
    aws_iam_role.runtime_role,
    aws_iam_role_policy.runtime_role_policy
  ]
}

# IAM Role for Agent Runtime
resource "aws_iam_role" "runtime_role" {
  count = local.create_runtime && var.runtime_role_arn == null ? 1 : 0
  name  = "${random_string.solution_prefix.result}-bedrock-agent-runtime-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock-agentcore.amazonaws.com"
        }
      }
    ]
  })

  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.runtime_tags
}

# IAM Policy for Agent Runtime
resource "aws_iam_role_policy" "runtime_role_policy" {
  count = local.create_runtime && var.runtime_role_arn == null ? 1 : 0
  name  = "${random_string.solution_prefix.result}-bedrock-agent-runtime-policy"
  role  = aws_iam_role.runtime_role[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRImageAccess"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = [
          "arn:aws:ecr:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:repository/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogStreams",
          "logs:CreateLogGroup"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*:log-stream:*"
        ]
      },
      {
        Sid    = "ECRTokenAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Resource = "*"
        Action   = "cloudwatch:PutMetricData"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "bedrock-agentcore"
          }
        }
      },
      {
        Sid    = "GetAgentAccessToken"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:GetWorkloadAccessToken",
          "bedrock-agentcore:GetWorkloadAccessTokenForJWT",
          "bedrock-agentcore:GetWorkloadAccessTokenForUserId"
        ]
        Resource = [
          "arn:aws:bedrock-agentcore:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default",
          "arn:aws:bedrock-agentcore:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default/workload-identity/${random_string.solution_prefix.result}_${var.runtime_name}-*"
        ]
      },
      {
        Sid    = "BedrockModelInvocation"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"
        ]
      }
    ]
  })
}

# – Bedrock Agent Core Runtime Endpoint –

locals {
  create_runtime_endpoint = var.create_runtime_endpoint
}

resource "awscc_bedrockagentcore_runtime_endpoint" "agent_runtime_endpoint" {
  count            = local.create_runtime_endpoint ? 1 : 0
  name             = "${random_string.solution_prefix.result}_${var.runtime_endpoint_name}"
  description      = var.runtime_endpoint_description
  agent_runtime_id = var.runtime_endpoint_agent_runtime_id != null ? var.runtime_endpoint_agent_runtime_id : try(awscc_bedrockagentcore_runtime.agent_runtime[0].agent_runtime_id, null)
  tags             = var.runtime_endpoint_tags
}
