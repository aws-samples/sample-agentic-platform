terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 3
  special = false
  upper   = false
}

# Get current region data
data "aws_region" "current" {}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Local values
locals {
  # Common naming pattern for all resources
  name_prefix = var.stack_name != "" ? "${var.stack_name}-" : ""
  suffix = random_string.suffix.result
  
  # Common tags for all resources
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Suffix      = local.suffix
    Project     = "Agentic Platform Sample"
  }
}

# KMS Module
module "kms" {
  source = "../../modules/kms"

  enable_kms_encryption   = var.enable_kms_encryption
  kms_deletion_window     = var.kms_deletion_window
  kms_key_administrators  = var.kms_key_administrators
  name_prefix            = local.name_prefix
  common_tags            = local.common_tags
}

# Networking Module
module "networking" {
  source = "../../modules/networking"

  name_prefix           = local.name_prefix
  suffix               = local.suffix
  common_tags          = local.common_tags
  enable_kms_encryption = var.enable_kms_encryption
  kms_key_arn          = module.kms.kms_key_arn
}
