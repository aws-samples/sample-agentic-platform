########################################################
# Global Variables
########################################################

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
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
  default     = ["arn:aws:iam::123456789012:assumed-role/Admin"]  # Empty list as default
}

########################################################
# EKS Variables
########################################################

variable "federated_role_name" {
  description = "IAM role name used for federation access to AWS"
  type        = string
  default     = ""  # Set a default or leave empty
}


########################################################
# Postgres Variables
########################################################

variable "postgres_iam_username" {
  description = "IAM username for Postgres"
  type        = string
  default     = "rdsuser"  
}

variable "postgres_deletion_protection" {
  description = "Enable deletion protection for Postgres"
  type        = bool
  default     = true
}

########################################################
# Cognito Variables
########################################################


variable "domain_name" {
  description = "Domain name for the application (used for Cognito callbacks). Leave as empty string to use default AWS domain."
  type        = string
  default     = ""
}

variable "use_custom_domain" {
  description = "Set to true if using a custom domain instead of AWS default domain"
  type        = bool
  default     = false
}

variable "enable_federated_identity" {
  description = "Enable Cognito Federated Identity Pool"
  type        = bool
  default     = true
}
