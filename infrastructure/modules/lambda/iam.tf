# -----------------------------------------------------------------------------
# IAM Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "this" {
  name = "${var.name_prefix}${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# -----------------------------------------------------------------------------
# CloudWatch Logs Policy
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "logging" {
  name = "${var.name_prefix}${var.function_name}-logging"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.this.arn}:*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# VPC Access (conditional)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "vpc_access" {
  count = var.subnet_ids != null ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role       = aws_iam_role.this.name
}

# -----------------------------------------------------------------------------
# X-Ray Tracing (conditional)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "xray" {
  count = var.tracing_mode != null ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
  role       = aws_iam_role.this.name
}

# -----------------------------------------------------------------------------
# Custom Managed Policy Attachments
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "custom" {
  count = length(var.policy_arns)

  policy_arn = var.policy_arns[count.index]
  role       = aws_iam_role.this.name
}

# -----------------------------------------------------------------------------
# Custom Inline Policy (conditional)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "inline" {
  count = var.inline_policy_json != null ? 1 : 0

  name   = "${var.name_prefix}${var.function_name}-inline"
  role   = aws_iam_role.this.id
  policy = var.inline_policy_json
}
