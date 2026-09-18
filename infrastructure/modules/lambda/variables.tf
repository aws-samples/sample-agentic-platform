# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------
variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "description" {
  description = "Description of the Lambda function"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Runtime Configuration
# -----------------------------------------------------------------------------
variable "runtime" {
  description = "Lambda runtime identifier (not needed for Image package type)"
  type        = string
  default     = null
}

variable "handler" {
  description = "Function entrypoint in the code (not needed for Image package type)"
  type        = string
  default     = null
}

variable "memory_size" {
  description = "Amount of memory in MB available to the function"
  type        = number
  default     = 128

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "Memory size must be between 128 and 10240 MB."
  }
}

variable "timeout" {
  description = "Amount of time the function has to run in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "Timeout must be between 1 and 900 seconds."
  }
}

# -----------------------------------------------------------------------------
# Deployment
# -----------------------------------------------------------------------------
variable "package_type" {
  description = "Lambda deployment package type (Zip or Image)"
  type        = string
  default     = "Zip"

  validation {
    condition     = contains(["Zip", "Image"], var.package_type)
    error_message = "Package type must be either 'Zip' or 'Image'."
  }
}

variable "filename" {
  description = "Path to the local ZIP file for deployment"
  type        = string
  default     = null
}

variable "source_code_hash" {
  description = "Base64-encoded SHA256 hash of the deployment package"
  type        = string
  default     = null
}

variable "s3_bucket" {
  description = "S3 bucket containing the deployment package"
  type        = string
  default     = null
}

variable "s3_key" {
  description = "S3 key of the deployment package"
  type        = string
  default     = null
}

variable "s3_object_version" {
  description = "S3 object version of the deployment package"
  type        = string
  default     = null
}

variable "image_uri" {
  description = "ECR image URI for container image deployment"
  type        = string
  default     = null
}

variable "publish" {
  description = "Whether to publish creation/change as a new Lambda function version"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "subnet_ids" {
  description = "List of subnet IDs for VPC-connected Lambda (enables VPC mode)"
  type        = list(string)
  default     = null
}

variable "security_group_ids" {
  description = "List of security group IDs for VPC-connected Lambda"
  type        = list(string)
  default     = null
}

# -----------------------------------------------------------------------------
# Environment & Encryption
# -----------------------------------------------------------------------------
variable "environment_variables" {
  description = "Map of environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for environment variable encryption and log group encryption"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
variable "log_retention_in_days" {
  description = "Number of days to retain CloudWatch log events"
  type        = number
  default     = 365

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention value."
  }
}

# -----------------------------------------------------------------------------
# Concurrency & Layers
# -----------------------------------------------------------------------------
variable "reserved_concurrent_executions" {
  description = "Number of reserved concurrent executions (-1 for unreserved)"
  type        = number
  default     = -1
}

variable "layers" {
  description = "List of Lambda layer ARNs to attach"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Dead Letter Queue & Tracing
# -----------------------------------------------------------------------------
variable "dead_letter_target_arn" {
  description = "ARN of the SQS queue or SNS topic for failed invocations"
  type        = string
  default     = null
}

variable "tracing_mode" {
  description = "X-Ray tracing mode (Active or PassThrough)"
  type        = string
  default     = null

  validation {
    condition     = var.tracing_mode == null ? true : contains(["Active", "PassThrough"], var.tracing_mode)
    error_message = "Tracing mode must be 'Active' or 'PassThrough'."
  }
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------
variable "policy_arns" {
  description = "List of IAM managed policy ARNs to attach to the Lambda role"
  type        = list(string)
  default     = []
}

variable "inline_policy_json" {
  description = "JSON string of an IAM policy to attach inline to the Lambda role"
  type        = string
  default     = null
}
