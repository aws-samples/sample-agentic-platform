########################################################
# Core Variables
########################################################

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

########################################################
# Base Infrastructure Variables (from base stack outputs)
########################################################

variable "name_prefix" {
  description = "Common name prefix used by resources"
  type        = string
  default     = "agent-ptfm-"
}

########################################################
# Networking Variables (from base stack)
########################################################

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "IDs of the public subnets"
  type        = list(string)
}

########################################################
# KMS Variables (from base stack)
########################################################

variable "enable_kms_encryption" {
  description = "Enable KMS encryption for resources"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "ARN of the KMS key"
  type        = string
  default     = null
}

variable "kms_key_id" {
  description = "ID of the KMS key"
  type        = string
  default     = null
}

########################################################
# EKS Configuration Variables
########################################################

variable "node_instance_types" {
  description = "List of instance types for EKS worker nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_scaling_config" {
  description = "Scaling configuration for EKS node group"
  type = object({
    desired_size = number
    max_size     = number
    min_size     = number
  })
  default = {
    desired_size = 4
    max_size     = 6
    min_size     = 2
  }
}

variable "node_disk_size" {
  description = "Disk size in GB for EKS worker nodes"
  type        = number
  default     = 20
}

variable "additional_admin_role_arns" {
  description = "List of additional IAM role ARNs to grant cluster admin access"
  type        = list(string)
  default     = []
}

variable "enable_eks_public_access" {
  description = "Enable public access to EKS APIs. Defaults to false"
  type        = bool
  default     = false
}

variable "deploy_inside_vpc" {
  description = "Deploy EKS cluster inside VPC. Defaults to false"
  type        = bool
  default     = false

}

########################################################
# PostgreSQL Aurora Configuration Variables
########################################################

variable "postgres_instance_count" {
  description = "Number of Aurora instances to create"
  type        = number
  default     = 2
}

variable "postgres_instance_class" {
  description = "Instance class for Aurora instances"
  type        = string
  default     = "db.t4g.medium"
}

variable "postgres_deletion_protection" {
  description = "Enable deletion protection for PostgreSQL cluster"
  type        = bool
  default     = false
}

variable "bastion_security_group_ids" {
  description = "List of bastion security group IDs that need access to PostgreSQL"
  type        = list(string)
  default     = []
}

########################################################
# Redis Agentic Cache Configuration Variables
########################################################

variable "redis_node_type" {
  description = "Instance class for Redis nodes"
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

variable "redis_num_cache_clusters" {
  description = "Number of cache clusters (nodes) in the replication group"
  type        = number
  default     = 2
}

variable "redis_maintenance_window" {
  description = "Maintenance window for Redis cluster"
  type        = string
  default     = "mon:03:00-mon:04:00"
}

variable "redis_snapshot_window" {
  description = "Daily time range for automated backups"
  type        = string
  default     = "02:00-03:00"
}

variable "redis_snapshot_retention_limit" {
  description = "Number of days to retain automatic snapshots"
  type        = number
  default     = 1
}

########################################################
# Cognito configuration
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

########################################################
# PostgreSQL Variables
########################################################

variable "postgres_iam_username" {
  description = "PostgreSQL IAM username for applications"
  type        = string
  default     = "rdsuser"
}

########################################################
# S3 Configuration Variables
########################################################

variable "s3_force_destroy" {
  description = "Allow S3 bucket to be destroyed even if it contains objects"
  type        = bool
  default     = true
}
