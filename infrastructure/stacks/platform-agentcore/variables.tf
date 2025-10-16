# Platform AgentCore Stack Variables
#
# This file defines all the input variables for the platform-agentcore stack.
# Variables are organized by component for clarity.

########################################################
# Core Configuration
########################################################

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

########################################################
# Networking Configuration (from foundation stack)
########################################################

variable "vpc_id" {
  description = "VPC ID where resources will be deployed"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

########################################################
# KMS Configuration (from foundation stack)
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

variable "kms_key_id" {
  description = "ID of the KMS key for encryption"
  type        = string
  default     = null
}

########################################################
# PostgreSQL Configuration
########################################################

variable "postgres_instance_count" {
  description = "Number of Aurora PostgreSQL instances"
  type        = number
  default     = 1
}

variable "postgres_instance_class" {
  description = "Instance class for Aurora PostgreSQL"
  type        = string
  default     = "db.t4g.medium"
}

variable "postgres_deletion_protection" {
  description = "Enable deletion protection for PostgreSQL cluster"
  type        = bool
  default     = false
}

variable "postgres_iam_username" {
  description = "IAM username for PostgreSQL authentication"
  type        = string
  default     = "postgres_iam_user"
}

########################################################
# Redis Configuration
########################################################

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

variable "redis_num_cache_clusters" {
  description = "Number of cache clusters in the replication group"
  type        = number
  default     = 2
}

variable "redis_maintenance_window" {
  description = "Maintenance window for Redis cluster"
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "redis_snapshot_window" {
  description = "Snapshot window for Redis cluster"
  type        = string
  default     = "03:00-04:00"
}

variable "redis_snapshot_retention_limit" {
  description = "Number of days to retain Redis snapshots"
  type        = number
  default     = 1
}

########################################################
# Cognito Configuration
########################################################

variable "domain_name" {
  description = "Domain name for Cognito (optional)"
  type        = string
  default     = ""
}

variable "use_custom_domain" {
  description = "Use custom domain for Cognito"
  type        = bool
  default     = false
}

variable "enable_federated_identity" {
  description = "Enable federated identity for Cognito"
  type        = bool
  default     = false
}

########################################################
# ECS LiteLLM Configuration
########################################################

variable "litellm_cpu" {
  description = "CPU units for LiteLLM ECS task (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "litellm_memory" {
  description = "Memory (MB) for LiteLLM ECS task"
  type        = number
  default     = 2048
}

variable "litellm_desired_count" {
  description = "Desired number of LiteLLM ECS tasks"
  type        = number
  default     = 1
}

variable "litellm_enable_auto_scaling" {
  description = "Enable auto scaling for LiteLLM ECS service"
  type        = bool
  default     = true
}

variable "litellm_min_capacity" {
  description = "Minimum number of LiteLLM ECS tasks for auto scaling"
  type        = number
  default     = 1
}

variable "litellm_max_capacity" {
  description = "Maximum number of LiteLLM ECS tasks for auto scaling"
  type        = number
  default     = 3
}

########################################################
# S3 Configuration
########################################################

variable "s3_force_destroy" {
  description = "Force destroy S3 buckets even if they contain objects"
  type        = bool
  default     = true
}
