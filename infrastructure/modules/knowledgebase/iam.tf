# IAM role for Bedrock Knowledge Base to access S3 Vectors and S3
resource "aws_iam_role" "kb_role" {
  name        = "${var.name_prefix}bedrock-kb-role"
  description = "Role for Bedrock Knowledge Base to access S3 Vectors and S3"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"
          }
        }
      }
    ]
  })

  tags = var.common_tags
}

# IAM policy for Bedrock to access S3 Vectors
resource "aws_iam_policy" "kb_vectors_access" {
  name        = "${var.name_prefix}bedrock-kb-vectors-access"
  description = "Policy for Bedrock Knowledge Base to access S3 Vectors"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3vectors:GetObject",
          "s3vectors:ListBucket",
          "s3vectors:DescribeIndex",
          "s3vectors:Query",
          "s3vectors:QueryVectors",
          "s3vectors:GetVectors",
          "s3vectors:PutVectors",
          "s3vectors:DeleteVectors",
          "s3vectors:PutObject",
          "s3vectors:DeleteObject"
        ]
        Resource = [
          aws_s3vectors_vector_bucket.kb_bucket.vector_bucket_arn,
          "${aws_s3vectors_vector_bucket.kb_bucket.vector_bucket_arn}/*",
          aws_s3vectors_index.kb_index.index_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.embedding_model}"
        ]
      }
    ]
  })

  tags = var.common_tags
}

# IAM policy for Bedrock to access S3 supplemental storage and documents bucket
resource "aws_iam_policy" "kb_s3_access" {
  name        = "${var.name_prefix}bedrock-kb-s3-access"
  description = "Policy for Bedrock Knowledge Base to access S3 supplemental storage and documents"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.kb_data.arn,
          "${aws_s3_bucket.kb_data.arn}/*",
          aws_s3_bucket.kb_documents.arn,
          "${aws_s3_bucket.kb_documents.arn}/*"
        ]
      }
    ]
  })

  tags = var.common_tags
}

# Attach S3 Vectors policy to role
resource "aws_iam_role_policy_attachment" "kb_vectors_access" {
  role       = aws_iam_role.kb_role.name
  policy_arn = aws_iam_policy.kb_vectors_access.arn
}

# Attach S3 policy to role
resource "aws_iam_role_policy_attachment" "kb_s3_access" {
  role       = aws_iam_role.kb_role.name
  policy_arn = aws_iam_policy.kb_s3_access.arn
}
