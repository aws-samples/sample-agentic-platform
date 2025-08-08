########################################################
# PostgreSQL Users Setup Outputs
########################################################

output "postgres_users_setup_complete" {
  description = "Indicates that PostgreSQL users and databases setup is complete"
  value       = true
}

output "litellm_secret_name" {
  description = "Name of the LiteLLM secret in AWS Secrets Manager"
  value       = local.platform_config.LITELLM_SECRET_NAME
  sensitive   = true
}

output "postgres_endpoint" {
  description = "PostgreSQL cluster endpoint"
  value       = local.platform_config.PG_WRITER_ENDPOINT
  sensitive   = true
}
