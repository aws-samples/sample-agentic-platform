# ECS LiteLLM Module Variables

########################################################
# Core Configuration
########################################################

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

variable "suffix" {
  description = "Suffix for unique resource naming"
  type        = string
}

########################################################
# Networking Configuration
########################################################

variable "vpc_id" {
  description = "VPC ID where resources will be deployed"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC for security group rules"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for load balancer"
  type        = list(string)
}

########################################################
# LiteLLM Configuration
########################################################

variable "litellm_secret_arn" {
  description = "ARN of the LiteLLM secret in Secrets Manager"
  type        = string
}

########################################################
# PostgreSQL Configuration
########################################################

variable "postgres_cluster_resource_id" {
  description = "PostgreSQL cluster resource ID for IAM authentication"
  type        = string
}

variable "postgres_cluster_endpoint" {
  description = "PostgreSQL cluster endpoint for database connection"
  type        = string
}

variable "postgres_secret_arn" {
  description = "ARN of the PostgreSQL secret in Secrets Manager"
  type        = string
}

########################################################
# Redis Configuration
########################################################

variable "redis_cluster_arn" {
  description = "Redis cluster ARN"
  type        = string
}

variable "redis_secret_arn" {
  description = "ARN of the Redis auth token secret"
  type        = string
}

########################################################
# ECS Configuration
########################################################

variable "cpu" {
  description = "CPU units for ECS task (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "memory" {
  description = "Memory (MB) for ECS task"
  type        = number
  default     = 2048
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1
}

variable "enable_auto_scaling" {
  description = "Enable auto scaling for ECS service"
  type        = bool
  default     = true
}

variable "min_capacity" {
  description = "Minimum number of ECS tasks for auto scaling"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks for auto scaling"
  type        = number
  default     = 3
}

########################################################
# KMS Configuration
########################################################

variable "enable_kms_encryption" {
  description = "Enable KMS encryption for supported resources"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for encryption"
  type        = string
  default     = null
}
# S3 Configuration Variables
variable "enable_s3_access_logging" {
  description = "Enable S3 access logging for the config bucket"
  type        = bool
  default     = false
}

variable "s3_access_log_bucket" {
  description = "S3 bucket for access logs (required if enable_s3_access_logging is true)"
  type        = string
  default     = null
}
