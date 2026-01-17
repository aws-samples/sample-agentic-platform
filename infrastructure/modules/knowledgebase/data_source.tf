# S3 bucket for knowledge base documents (data source)
resource "aws_s3_bucket" "kb_documents" {
  #checkov:skip=CKV2_AWS_62:Event notifications not needed for document ingestion bucket
  #checkov:skip=CKV2_AWS_61:Lifecycle policies not needed - documents managed by user
  #checkov:skip=CKV_AWS_18:Access logging optional for internal storage bucket
  #checkov:skip=CKV_AWS_145:KMS encryption optional - uses AES256 by default
  #checkov:skip=CKV_AWS_144:Cross-region replication not needed for dev environment
  #checkov:skip=CKV_AWS_21:Versioning not needed for document storage
  bucket = "${var.name_prefix}kb-documents-${var.suffix}"

  tags = merge(var.common_tags, {
    Name    = "Knowledge Base Documents Bucket"
    Purpose = "Bedrock Knowledge Base Data Source"
  })
}

# Block public access
resource "aws_s3_bucket_public_access_block" "kb_documents" {
  bucket = aws_s3_bucket.kb_documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bedrock data source pointing to S3 bucket
resource "aws_bedrockagent_data_source" "kb_s3" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.kb.id
  name              = "${var.name_prefix}s3-data-source"
  description       = "S3 data source for knowledge base documents"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.kb_documents.arn
    }
  }

  depends_on = [
    aws_bedrockagent_knowledge_base.kb
  ]
}
