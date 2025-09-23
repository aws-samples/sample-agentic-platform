# ECS Cluster Configuration

resource "aws_ecs_cluster" "main" {
  # checkov:skip=CKV_AWS_65: KMS encryption is conditionally enabled
  # checkov:skip=CKV_AWS_224: KMS encryption is conditionally enabled
  name = "${var.name_prefix}agentcore-cluster"

  configuration {
    execute_command_configuration {
      # checkov:skip=CKV_AWS_65: KMS encryption is conditionally enabled
      kms_key_id = var.enable_kms_encryption ? var.kms_key_arn : null
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = var.enable_kms_encryption
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}
