variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

variable "suffix" {
  description = "Random suffix for unique resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
}

variable "kb_name" {
  description = "Name for the knowledge base"
  type        = string
  default     = "agentic-platform-kb"
}

variable "embedding_model" {
  description = "Bedrock embedding model to use"
  type        = string
  default     = "amazon.nova-2-multimodal-embeddings-v1:0"
}

variable "vector_dimension" {
  description = "Dimension of the embedding vectors"
  type        = number
  default     = 1024 # Nova 2 multimodal uses 1024 dimensions
}

variable "embedding_data_type" {
  description = "Data type for embeddings"
  type        = string
  default     = "FLOAT32"
}

variable "distance_metric" {
  description = "Distance metric for vector search"
  type        = string
  default     = "cosine"
  validation {
    condition     = contains(["cosine", "euclidean", "dot_product"], var.distance_metric)
    error_message = "Distance metric must be one of: cosine, euclidean, dot_product"
  }
}

variable "enable_kms_encryption" {
  description = "Enable KMS encryption for S3 bucket"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "ARN of the KMS key to use for S3 encryption"
  type        = string
  default     = null
}
