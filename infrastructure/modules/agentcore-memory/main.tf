# – Bedrock Agent Core Runtime –
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}


resource "awscc_bedrockagentcore_memory" "agentcore_memory" {
    event_expiry_duration = var.expiration_duration
    name = var.memory_name
}