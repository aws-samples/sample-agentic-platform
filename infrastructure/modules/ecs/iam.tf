# IAM Roles and Policies

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.name_prefix}${local.service_name}-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for Secrets Manager access
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${var.name_prefix}${local.service_name}-secrets-policy"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          var.litellm_secret_arn,
          var.postgres_secret_arn,
          var.redis_secret_arn
        ]
      }
    ], var.enable_kms_encryption ? [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = [var.kms_key_arn]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ] : [])
  })
}

# ECS Task Role (for application permissions)
resource "aws_iam_role" "ecs_task" {
  name = "${var.name_prefix}${local.service_name}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# Policy for RDS IAM authentication
resource "aws_iam_role_policy" "ecs_task_rds_connect" {
  name = "${var.name_prefix}${local.service_name}-rds-connect-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = [
          "arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${var.postgres_cluster_resource_id}/litellm"
        ]
      }
    ]
  })
}

# Policy for Bedrock access (for LiteLLM to proxy AI models)
resource "aws_iam_role_policy" "ecs_task_bedrock" {
  name = "${var.name_prefix}${local.service_name}-bedrock-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          # Allow access to all models in the account across all regions
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:model/*",
          # Allow access to all inference profiles in the account across all regions
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/*",
          # Allow access to AWS foundation models
          "arn:aws:bedrock:*::foundation-model/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:ListFoundationModels",
          "bedrock:GetFoundationModel"
        ]
        Resource = [
          # These are read-only list operations
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:*"
        ]
      }
    ]
  })
}

# Policy for S3 config access
resource "aws_iam_role_policy" "ecs_task_s3_config" {
  name = "${var.name_prefix}${local.service_name}-s3-config-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.litellm_config.arn}/*"
        ]
      }
    ]
  })
}
