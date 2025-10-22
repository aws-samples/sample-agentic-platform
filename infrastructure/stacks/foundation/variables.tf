########################################################
# Global Variables
########################################################

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "stack_name" {
  description = "Name of the stack to prefix to resource names"
  type        = string
  default     = "agent-ptfm"
}

########################################################
# KMS Variables
########################################################

variable "enable_kms_encryption" {
  description = "Enable KMS encryption for resources that support it"
  type        = bool
  default     = false
}

variable "kms_deletion_window" {
  description = "Waiting period in days before KMS key is deleted"
  type        = number
  default     = 7
}

variable "kms_key_administrators" {
  description = "List of ARNs of IAM users/roles that can administer the KMS key"
  type        = list(string)
  default     = []
}
