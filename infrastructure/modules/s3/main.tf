########################################################
# S3 Bucket
########################################################

resource "aws_s3_bucket" "this" {
  # checkov:skip=CKV_AWS_144:Cross-region replication not required for sample website - adds unnecessary cost and complexity
  # checkov:skip=CKV_AWS_145:S3 default encryption (AES256) is sufficient for static website content, KMS not required
  # checkov:skip=CKV_AWS_21:S3 versioning disabled - website content is versioned through CI/CD and stored in Git
  # checkov:skip=CKV2_AWS_62:Event notifications not required for static website hosting - no automated processing needed
  # checkov:skip=CKV_AWS_18:Access logging not needed for sample UI.
  # bucket name omitted - Terraform will generate a unique name automatically
  force_destroy = var.force_destroy

  tags = merge(var.common_tags, {
    Name = "S3 Bucket"
    Type = var.bucket_type
  })
}

########################################################
# S3 Bucket Versioning
########################################################

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

########################################################
# S3 Bucket Server Side Encryption
########################################################

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.encryption_algorithm
      kms_master_key_id = var.encryption_algorithm == "aws:kms" ? var.kms_key_id : null
    }
    bucket_key_enabled = var.encryption_algorithm == "aws:kms" ? true : true
  }
}

########################################################
# S3 Bucket Public Access Block - Always Secure
########################################################

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  # Always block all public access - no exceptions
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
