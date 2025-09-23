variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "configuration_sections" {
  description = "Map of configuration sections from different modules"
  type        = any
  default     = {}
}

variable "parameter_base_path" {
  description = "Base path for parameter store parameters"
  type        = string
  default     = "/agentic-platform/config"
}

variable "parameter_name" {
  description = "Custom parameter name (overrides default path/environment naming)"
  type        = string
  default     = null
}
