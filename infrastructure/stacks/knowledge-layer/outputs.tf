# Knowledge Base Outputs
output "knowledge_base_id" {
  description = "ID of the Bedrock Knowledge Base"
  value       = module.knowledgebase.knowledge_base_id
}

output "knowledge_base_arn" {
  description = "ARN of the Bedrock Knowledge Base"
  value       = module.knowledgebase.knowledge_base_arn
}

output "vector_bucket_name" {
  description = "Name of the S3 Vectors bucket"
  value       = module.knowledgebase.vector_bucket_name
}

output "vector_bucket_arn" {
  description = "ARN of the S3 Vectors bucket"
  value       = module.knowledgebase.vector_bucket_arn
}

output "index_name" {
  description = "Name of the S3 Vectors index"
  value       = module.knowledgebase.index_name
}

output "index_arn" {
  description = "ARN of the S3 Vectors index"
  value       = module.knowledgebase.index_arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for supplemental data storage"
  value       = module.knowledgebase.s3_bucket_name
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for supplemental data storage"
  value       = module.knowledgebase.s3_bucket_arn
}

output "kb_role_arn" {
  description = "ARN of the IAM role for the Knowledge Base"
  value       = module.knowledgebase.kb_role_arn
}

output "data_source_id" {
  description = "ID of the Bedrock data source"
  value       = module.knowledgebase.data_source_id
}

output "documents_bucket_name" {
  description = "Name of the S3 bucket for knowledge base documents"
  value       = module.knowledgebase.documents_bucket_name
}

output "documents_bucket_arn" {
  description = "ARN of the S3 bucket for knowledge base documents"
  value       = module.knowledgebase.documents_bucket_arn
}

# Parameter Store Outputs
output "parameter_store_name" {
  description = "Name of the Parameter Store parameter containing configuration"
  value       = module.parameter_store.parameter_name
}

output "parameter_store_arn" {
  description = "ARN of the Parameter Store parameter"
  value       = module.parameter_store.parameter_arn
}

output "configuration_json" {
  description = "Complete configuration as JSON"
  value       = module.parameter_store.configuration_json
  sensitive   = true
}
