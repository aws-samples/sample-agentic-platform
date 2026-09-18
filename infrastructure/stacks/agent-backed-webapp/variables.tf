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
  default     = "agent-webapp"
}

########################################################
# Lambda Configuration
########################################################

variable "lambda_filename" {
  description = "Path to the Lambda deployment ZIP file"
  type        = string
  default     = null
}

variable "lambda_source_code_hash" {
  description = "Base64-encoded SHA256 hash of the Lambda deployment package"
  type        = string
  default     = null
}

variable "lambda_s3_bucket" {
  description = "S3 bucket containing the Lambda deployment package"
  type        = string
  default     = null
}

variable "lambda_s3_key" {
  description = "S3 key of the Lambda deployment package"
  type        = string
  default     = null
}

variable "lambda_runtime" {
  description = "Lambda runtime identifier"
  type        = string
  default     = "python3.12"
}

variable "lambda_handler" {
  description = "Lambda function entrypoint"
  type        = string
  default     = "index.handler"
}

variable "lambda_memory_size" {
  description = "Lambda memory in MB"
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 60
}

########################################################
# Cognito Configuration
########################################################

variable "domain_name" {
  description = "Domain name for the application (used for Cognito callbacks). Leave empty to use default."
  type        = string
  default     = ""
}

variable "use_custom_domain" {
  description = "Set to true if using a custom domain instead of AWS default domain"
  type        = bool
  default     = false
}
