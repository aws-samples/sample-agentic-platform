# S3 bucket for supplemental data storage (multimodal chunks)
resource "aws_s3_bucket" "kb_data" {
  #checkov:skip=CKV2_AWS_62:Event notifications not needed for Bedrock-managed supplemental storage
  #checkov:skip=CKV2_AWS_61:Lifecycle policies not needed - Bedrock manages chunk lifecycle
  #checkov:skip=CKV_AWS_18:Access logging optional for internal storage bucket
  #checkov:skip=CKV_AWS_145:KMS encryption optional - uses AES256 by default
  #checkov:skip=CKV_AWS_144:Cross-region replication not needed for dev environment
  #checkov:skip=CKV_AWS_21:Versioning not needed for supplemental storage chunks
  bucket = "${var.name_prefix}kb-data-${var.suffix}"

  tags = merge(var.common_tags, {
    Name    = "Knowledge Base Data Bucket"
    Purpose = "Bedrock Knowledge Base Supplemental Storage"
  })
}

# Block public access
resource "aws_s3_bucket_public_access_block" "kb_data" {
  bucket = aws_s3_bucket.kb_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Vectors bucket for knowledge base documents
resource "aws_s3vectors_vector_bucket" "kb_bucket" {
  vector_bucket_name = "${var.name_prefix}kb-vectors-${var.suffix}"

  tags = merge(var.common_tags, {
    Name    = "Knowledge Base Vectors Bucket"
    Purpose = "Bedrock Knowledge Base"
  })
}

# S3 Vectors index for semantic search
resource "aws_s3vectors_index" "kb_index" {
  index_name         = "${var.name_prefix}kb-index-${var.suffix}"
  vector_bucket_name = aws_s3vectors_vector_bucket.kb_bucket.vector_bucket_name

  data_type       = lower(var.embedding_data_type)
  dimension       = var.vector_dimension
  distance_metric = var.distance_metric

  tags = merge(var.common_tags, {
    Name    = "Knowledge Base Index"
    Purpose = "Bedrock Knowledge Base Semantic Search"
  })
}
