terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Get current AWS account and region data
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
