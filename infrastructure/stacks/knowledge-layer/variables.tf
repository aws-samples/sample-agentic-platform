# Core Configuration
variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "knwl-"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

# Knowledge Base Configuration
variable "kb_name" {
  description = "Name for the knowledge base"
  type        = string
  default     = "agentic-kb"
}

variable "embedding_model" {
  description = "Bedrock embedding model to use"
  type        = string
  default     = "amazon.nova-2-multimodal-embeddings-v1:0"
}

variable "vector_dimension" {
  description = "Dimension of the embedding vectors"
  type        = number
  default     = 1024
}

variable "distance_metric" {
  description = "Distance metric for vector search (cosine, euclidean, dot_product)"
  type        = string
  default     = "cosine"
}

# KMS Encryption Configuration
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

# Kubernetes Integration (Optional)
variable "eks_cluster_name" {
  description = "Name of the EKS cluster to deploy ConfigMap to (optional - leave empty to skip K8s deployment)"
  type        = string
  default     = ""
}
