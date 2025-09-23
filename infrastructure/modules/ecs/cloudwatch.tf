# CloudWatch Log Groups

resource "aws_cloudwatch_log_group" "litellm" {
  # checkov:skip=CKV_AWS_158: KMS encryption is conditionally enabled
  name              = "/ecs/${var.name_prefix}${local.service_name}"
  retention_in_days = 365
  kms_key_id        = var.enable_kms_encryption ? var.kms_key_arn : null

  tags = var.common_tags
}

resource "aws_cloudwatch_log_group" "ecs_exec" {
  # checkov:skip=CKV_AWS_158: KMS encryption is conditionally enabled
  name              = "/ecs/${var.name_prefix}exec"
  retention_in_days = 365
  kms_key_id        = var.enable_kms_encryption ? var.kms_key_arn : null

  tags = var.common_tags
}
