// VPC Flow Logs Configuration
resource "aws_flow_log" "vpc_flow_log" {
  iam_role_arn    = aws_iam_role.vpc_flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log_group.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}

// CloudWatch Log Group for Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_log_group" {
  // checkov:skip=CKV_AWS_158: KMS encryption is conditionally enabled based on var.enable_kms_encryption
  name              = "/aws/vpc/flow-logs/${var.name_prefix}vpc-${var.suffix}"
  retention_in_days = 365
  kms_key_id        = var.enable_kms_encryption ? var.kms_key_arn : null

  tags = var.common_tags
}

// IAM Role for VPC Flow Logs
resource "aws_iam_role" "vpc_flow_log_role" {
  name = "${var.name_prefix}vpcflow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

// IAM Policy for VPC Flow Logs
resource "aws_iam_role_policy" "vpc_flow_log_policy" {
  name = "${var.name_prefix}vpc-flow-log-policy"
  role = aws_iam_role.vpc_flow_log_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect = "Allow"
        Resource = [
          aws_cloudwatch_log_group.vpc_flow_log_group.arn,
          "${aws_cloudwatch_log_group.vpc_flow_log_group.arn}:*"
        ]
      }
    ]
  })
}
