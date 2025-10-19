# Create a secret to store the LiteLLM API key for our default agent. 
# As you add more agents, you'll want to add a secret for each agent to throttle them individually. 
# For this sample repo, we default to using the same key for all agents.
resource "aws_secretsmanager_secret" "agent_secret" {
  # checkov:skip=CKV2_AWS_57: As a sample, its a bit heavy handed to rotate the secret. This is called out in the readme. 
  # checkov:skip=CKV_AWS_149: KMS key is conditionally used based on var.enable_kms_encryption
  name                    = "${var.name_prefix}agent-secret"
  description             = "Generic secret to store litellm api key for agents"
  recovery_window_in_days = 0  # Allow immediate deletion without waiting period
  kms_key_id              = var.enable_kms_encryption ? var.kms_key_arn : null
  
  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "agent_secret" {
  secret_id     = aws_secretsmanager_secret.agent_secret.id
  secret_string = jsonencode({
    # LiteLLM master key
    LITELLM_KEY = "sk-${random_string.litellm_master_key_suffix.result}"
  })
}
