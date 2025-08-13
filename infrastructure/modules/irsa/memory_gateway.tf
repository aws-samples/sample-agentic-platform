# IRSA for Memory Gateway - PostgreSQL access
resource "aws_iam_policy" "memory_gateway_postgres_policy" {
  name        = "${var.name_prefix}memory-gateway-postgres-policy"
  description = "Policy to allow Memory Gateway to access PostgreSQL and retrieve its password"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Allow access to the Postgres master password secret
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.postgres_secret_arns
      },
      # Allow RDS IAM authentication (if using IAM auth instead of password)
      {
        Effect = "Allow"
        Action = [ # nosemgrep: no-iam-resource-exposure
          "rds-db:connect"
        ]
        Resource = var.postgres_db_user_arns
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role" "memory_gateway_role" {
  name = "${var.name_prefix}memory-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(var.cluster_oidc_issuer_url, "https://", "")}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub": "system:serviceaccount:default:memory-gateway-sa"
          }
        }
      }
    ]
  })

  tags = var.common_tags
}

# Attach policy to the Memory Gateway role
resource "aws_iam_role_policy_attachment" "memory_gateway_postgres_attachment" {
  policy_arn = aws_iam_policy.memory_gateway_postgres_policy.arn
  role       = aws_iam_role.memory_gateway_role.name
}

# Add additional policies if needed (e.g., CloudWatch logging)
resource "aws_iam_role_policy_attachment" "memory_gateway_cloudwatch_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  role       = aws_iam_role.memory_gateway_role.name
}

# Add Bedrock AgentCore Memory access
resource "aws_iam_role_policy_attachment" "memory_gateway_bedrock_agentcore_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/BedrockAgentCoreFullAccess"
  role       = aws_iam_role.memory_gateway_role.name
}
