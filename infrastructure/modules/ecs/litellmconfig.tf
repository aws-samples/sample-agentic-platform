# LiteLLM Configuration S3 Bucket and Config File

# S3 bucket for LiteLLM config. This is currently the only way to inject config into litellm running in Fargate.
resource "aws_s3_bucket" "litellm_config" {
  # checkov:skip=CKV2_AWS_62: No need for event notifications for config changes. 
  # checkov:skip=CKV2_AWS_61: No need for lifecycle for config changes. 
  # checkov:skip=CKV_AWS_144: No need for cross region replication for litellm config.
  tags = var.common_tags
}

resource "aws_s3_bucket_versioning" "litellm_config" {
  bucket = aws_s3_bucket.litellm_config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "litellm_config" {
  bucket = aws_s3_bucket.litellm_config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? var.kms_key_arn : null
    }
  }
}

resource "aws_s3_bucket_public_access_block" "litellm_config" {
  bucket = aws_s3_bucket.litellm_config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "litellm_config" {
  count  = var.enable_s3_access_logging ? 1 : 0
  bucket = aws_s3_bucket.litellm_config.id

  target_bucket = var.s3_access_log_bucket
  target_prefix = "litellm-config-access-logs/"
}

# LiteLLM config YAML content
locals {
  litellm_config_yaml = <<-EOT
model_list:
  - model_name: anthropic.claude-sonnet-4-20250514-v1:0
    litellm_params:
      model: bedrock/converse/us.anthropic.claude-sonnet-4-20250514-v1:0

  - model_name: us.anthropic.claude-3-5-haiku-20241022-v1:0
    litellm_params:
      model: bedrock/us.anthropic.claude-3-5-haiku-20241022-v1:0

  - model_name: us.anthropic.claude-3-haiku-20240307-v1:0
    litellm_params:
      model: bedrock/us.anthropic.claude-3-haiku-20240307-v1:0

  - model_name: us.amazon.nova-pro-v1:0
    litellm_params:
      model: bedrock/us.amazon.nova-pro-v1:0

  - model_name: us.amazon.nova-lite-v1:0
    litellm_params:
      model: bedrock/us.amazon.nova-lite-v1:0

  - model_name: us.amazon.nova-micro-v1:0
    litellm_params:
      model: bedrock/us.amazon.nova-micro-v1:0

  - model_name: us.meta.llama3-3-70b-instruct-v1:0
    litellm_params:
      model: bedrock/us.meta.llama3-3-70b-instruct-v1:0

  - model_name: us.anthropic.claude-3-7-sonnet-20250219-v1:0
    litellm_params:
      model: bedrock/converse/us.anthropic.claude-3-7-sonnet-20250219-v1:0

  - model_name: amazon.titan-embed-text-v2:0
    litellm_params:
      model: bedrock/amazon.titan-embed-text-v2:0

general_settings:
  ui: true
  master_key: os.environ/LITELLM_MASTER_KEY
  health_check_details: false
  disable_spend_logs: true
  public_routes: ["/health", "/health/livenessz", "/health/readiness"]
  
health_check:
  enable_health_check: true
  health_check_interval: 30

router_settings:
  redis_host: os.environ/REDIS_HOST
  redis_password: os.environ/REDIS_PASSWORD
  redis_port: os.environ/REDIS_PORT
EOT
}

# Upload config to S3
resource "aws_s3_object" "litellm_config" {
  bucket  = aws_s3_bucket.litellm_config.id
  key     = "litellm_proxy_config.yaml"
  content = local.litellm_config_yaml
  
  tags = var.common_tags
}
