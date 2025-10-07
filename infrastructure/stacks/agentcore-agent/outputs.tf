output "runtime_arn" {
  description = "ARN of the created runtime"
  value       = module.agentcore.agent_runtime_arn
}

output "runtime_endpoint_arn" {
  description = "ARN of the created runtime endpoint"
  value       = module.agentcore.agent_runtime_endpoint_arn
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.agent_repo.repository_url
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.agent_repo.name
}
