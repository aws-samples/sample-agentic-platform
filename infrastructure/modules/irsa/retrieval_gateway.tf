# IRSA for Retrieval Gateway - Bedrock Knowledge Base operations
resource "aws_iam_policy" "bedrock_retrieval_policy" {
  name        = "${var.name_prefix}bedrock-retrieval-policy"
  description = "Policy to allow Bedrock Knowledge Base operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate",
          "bedrock:ListKnowledgeBases",
          "bedrock:GetKnowledgeBase"
        ]
        Resource = [
          # Allow operations on all knowledge bases in the account across all regions
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:knowledge-base/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"  # Required for combining retrieval with generation
        ]
        Resource = [
          # Allow access to all models in the account across all regions (needed for generation)
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:model/*",
          # Allow access to AWS foundation models
          "arn:aws:bedrock:*::foundation-model/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:ListKnowledgeBases"
        ]
        Resource = [
          # This is a list operation that requires a broader scope
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:*"
        ]
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role" "retrieval_gateway_role" {
  name = "${var.name_prefix}retrieval-gateway-role"

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
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub": "system:serviceaccount:default:retrieval-gateway-sa"
          }
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "bedrock_retrieval_attachment" {
  policy_arn = aws_iam_policy.bedrock_retrieval_policy.arn
  role       = aws_iam_role.retrieval_gateway_role.name
}

# Policy to allow access to LiteLLM secret
resource "aws_iam_policy" "retrieval_gateway_secrets_policy" {
  name        = "${var.name_prefix}retrieval-gateway-secrets-policy"
  description = "Policy to allow Retrieval Gateway to access secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = concat(var.litellm_secret_arns, var.agent_secret_arns)
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "retrieval_gateway_secrets_attachment" {
  policy_arn = aws_iam_policy.retrieval_gateway_secrets_policy.arn
  role       = aws_iam_role.retrieval_gateway_role.name
}
