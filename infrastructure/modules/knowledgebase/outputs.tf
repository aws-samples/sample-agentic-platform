# Individual outputs for Terraform consumers
output "knowledge_base_id" {
  description = "ID of the Bedrock Knowledge Base"
  value       = aws_bedrockagent_knowledge_base.kb.id
}

output "knowledge_base_arn" {
  description = "ARN of the Bedrock Knowledge Base"
  value       = aws_bedrockagent_knowledge_base.kb.arn
}

output "vector_bucket_name" {
  description = "Name of the S3 Vectors bucket"
  value       = aws_s3vectors_vector_bucket.kb_bucket.vector_bucket_name
}

output "vector_bucket_arn" {
  description = "ARN of the S3 Vectors bucket"
  value       = aws_s3vectors_vector_bucket.kb_bucket.vector_bucket_arn
}

output "index_name" {
  description = "Name of the S3 Vectors index"
  value       = aws_s3vectors_index.kb_index.index_name
}

output "index_arn" {
  description = "ARN of the S3 Vectors index"
  value       = aws_s3vectors_index.kb_index.index_arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for supplemental data storage"
  value       = aws_s3_bucket.kb_data.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for supplemental data storage"
  value       = aws_s3_bucket.kb_data.arn
}

output "kb_role_arn" {
  description = "ARN of the IAM role for the Knowledge Base"
  value       = aws_iam_role.kb_role.arn
}

output "data_source_id" {
  description = "ID of the Bedrock data source"
  value       = aws_bedrockagent_data_source.kb_s3.data_source_id
}

output "documents_bucket_name" {
  description = "Name of the S3 bucket for knowledge base documents"
  value       = aws_s3_bucket.kb_documents.id
}

output "documents_bucket_arn" {
  description = "ARN of the S3 bucket for knowledge base documents"
  value       = aws_s3_bucket.kb_documents.arn
}

# Structured config output for Parameter Store integration
output "config" {
  description = "Knowledge Base configuration for parameter store (minimal)"
  value = {
    KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.kb.id
  }
}
