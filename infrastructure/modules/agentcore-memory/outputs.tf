# – Bedrock Agent Core Runtime Outputs –

output "memory_id" {
  description = "ID of the created Bedrock AgentCore Runtime"
  value       = try(awscc_bedrockagentcore_memory.agentcore_memory.memory_id, null)
}

output "memory_arn" {
  description = "ARN of the created Bedrock AgentCore Runtime"
  value       = try(awscc_bedrockagentcore_memory.agentcore_memory.memory_arn, null)
}