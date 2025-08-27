# ECS Module
#
# This module creates an ECS cluster and service to run LiteLLM as a containerized service.
# Components are split across multiple files for better organization:
# - main.tf: Core configuration and data sources
# - ecr.tf: ECR repository for container images
# - ecs-cluster.tf: ECS cluster configuration
# - ecs-service.tf: ECS service and task definition
# - alb.tf: Application Load Balancer
# - security-groups.tf: Security groups
# - iam.tf: IAM roles and policies
# - cloudwatch.tf: CloudWatch log groups
# - autoscaling.tf: Auto scaling configuration

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Get current region and account data
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Local values
locals {
  service_name = "litellm"
  container_port = 4000
  health_check_path = "/health/liveliness"
}
