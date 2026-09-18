variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "image_version" {
  description = "Docker image version tag"
  type        = string
  default     = "latest"
}

variable "source_bucket_name" {
  description = "S3 bucket containing source code folders"
  type        = string
}

variable "results_bucket_name" {
  description = "S3 bucket for storing transformation results"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "max_parallel_jobs" {
  description = "Maximum number of parallel transformation jobs"
  type        = number
  default     = 4

  validation {
    condition     = var.max_parallel_jobs >= 1 && var.max_parallel_jobs <= 10
    error_message = "Max parallel jobs must be between 1 and 10."
  }
}

variable "task_cpu" {
  description = "CPU units for ECS task (1024 = 1 vCPU)"
  type        = string
  default     = "2048"

  validation {
    condition     = contains(["256", "512", "1024", "2048", "4096"], var.task_cpu)
    error_message = "Task CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "task_memory" {
  description = "Memory for ECS task in MB"
  type        = string
  default     = "4096"

  validation {
    condition     = contains(["512", "1024", "2048", "4096", "8192", "16384"], var.task_memory)
    error_message = "Task memory must be one of: 512, 1024, 2048, 4096, 8192, 16384."
  }
}
