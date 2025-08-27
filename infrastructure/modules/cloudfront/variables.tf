variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "suffix" {
  description = "Suffix for resource names"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for the SPA website"
  type        = string
}

variable "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  type        = string
}

variable "environment" {
  description = "Environment name for the comment"
  type        = string
  default     = "dev"
}

variable "vpc_origin_arns" {
  description = "List of VPC origin ARNs (e.g., ALB ARNs) to create VPC origins for"
  type        = list(string)
  default     = []
}
