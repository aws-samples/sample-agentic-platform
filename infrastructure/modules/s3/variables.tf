variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "force_destroy" {
  description = "Allow bucket to be destroyed even if it contains objects"
  type        = bool
  default     = false
}

variable "versioning_enabled" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = false
}

variable "encryption_algorithm" {
  description = "Server-side encryption algorithm (AES256 or aws:kms)"
  type        = string
  default     = "AES256"
  validation {
    condition     = contains(["AES256", "aws:kms"], var.encryption_algorithm)
    error_message = "Encryption algorithm must be either 'AES256' or 'aws:kms'."
  }
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (required if encryption_algorithm is aws:kms)"
  type        = string
  default     = null
}

variable "enable_lifecycle_configuration" {
  description = "Enable lifecycle configuration for the bucket"
  type        = bool
  default     = false
}

variable "lifecycle_rules" {
  description = "List of lifecycle rules"
  type = list(object({
    id                                = string
    status                           = string
    filter_prefix                    = optional(string, "")
    abort_incomplete_multipart_days  = optional(number, 7)
    expiration_days                  = optional(number)
    noncurrent_version_expiration_days = optional(number)
  }))
  default = []
}

variable "enable_bucket_policy" {
  description = "Enable custom bucket policy"
  type        = bool
  default     = false
}

variable "bucket_policy_json" {
  description = "JSON policy document for the bucket"
  type        = string
  default     = null
}

variable "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN for OAC access (optional)"
  type        = string
  default     = null
}

variable "enable_cloudfront_oac_policy" {
  description = "Enable CloudFront Origin Access Control policy"
  type        = bool
  default     = false
}

variable "bucket_type" {
  description = "Type of bucket for tagging purposes"
  type        = string
  default     = "General"
}
