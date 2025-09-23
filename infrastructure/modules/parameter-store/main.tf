# Parameter Store Module
#
# This module creates AWS SSM Parameter Store entries for configuration values.
# 
# This approach solves a chicken-and-egg problem: we want the entire stack to deploy 
# in one Terraform run for this example, but the EKS cluster API is private and we're 
# deploying from outside the VPC. We can't deploy directly to the cluster during initial 
# creation since Terraform can't reach the private API endpoint.
#
# Solution: Store configuration in Parameter Store, then use External Secrets Operator (ESO) 
# to pull these values into the cluster as a ConfigMap after everything is running.
# Alternatively, use a second Terraform apply to create Kubernetes ConfigMaps directly.
#
# For sensitive data (passwords, API keys, etc.), use AWS Secrets Manager instead.

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Get current region data
data "aws_region" "current" {}

# Local values
locals {
  # Common tags for all parameters
  parameter_tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      Terraform   = "true"
      Service     = "agentic-platform"
    }
  )
  
  # Flatten all configuration sections into a single configuration object
  flattened_config = merge(
    # Add core infrastructure values
    {
      AWS_DEFAULT_REGION = var.aws_region
      ENVIRONMENT        = var.environment
      REGION            = var.aws_region
    },
    # Merge all configuration sections from modules
    flatten([
      for section_name, section_config in var.configuration_sections : [
        for key, value in section_config : {
          "${key}" = value
        }
      ]
    ])...
  )
}

# Single parameter store with all configuration values in a flat structure
resource "aws_ssm_parameter" "agentic_platform_config" {
  name        = var.parameter_name != null ? var.parameter_name : "${var.parameter_base_path}/${var.environment}"
  description = "All configuration values for the Agentic Platform"
  type        = "String"
  value       = jsonencode(local.flattened_config)
  tags        = local.parameter_tags
}
