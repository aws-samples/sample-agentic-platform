# Platform AgentCore Stack Outputs
#
# This file defines all the outputs from the platform-agentcore stack.
# Outputs are organized by component for clarity.

########################################################
# ECS LiteLLM Outputs
########################################################

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_litellm.ecs_cluster_name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs_litellm.ecs_cluster_arn
}

output "litellm_service_name" {
  description = "Name of the LiteLLM ECS service"
  value       = module.ecs_litellm.service_name
}

output "litellm_service_arn" {
  description = "ARN of the LiteLLM ECS service"
  value       = module.ecs_litellm.service_arn
}

output "litellm_load_balancer_dns" {
  description = "DNS name of the LiteLLM load balancer"
  value       = module.ecs_litellm.load_balancer_dns_name
}

output "litellm_load_balancer_url" {
  description = "URL of the LiteLLM service"
  value       = "http://${module.ecs_litellm.load_balancer_dns_name}"
}

# ECR repository removed - using official LiteLLM image from ghcr.io/berriai/litellm:main-latest

########################################################
# PostgreSQL Outputs
########################################################

output "postgres_cluster_endpoint" {
  description = "Aurora PostgreSQL cluster endpoint"
  value       = module.postgres_aurora.cluster_endpoint
}

output "postgres_cluster_port" {
  description = "Aurora PostgreSQL cluster port"
  value       = module.postgres_aurora.cluster_port
}

output "postgres_cluster_id" {
  description = "Aurora PostgreSQL cluster ID"
  value       = module.postgres_aurora.cluster_id
}

output "postgres_master_user_secret_arn" {
  description = "ARN of the PostgreSQL master user secret"
  value       = module.postgres_aurora.master_user_secret_arn
}

########################################################
# Redis Outputs
########################################################

output "redis_primary_endpoint" {
  description = "Redis primary endpoint address"
  value       = module.redis.primary_endpoint_address
}

output "redis_cluster_arn" {
  description = "Redis cluster ARN"
  value       = module.redis.cluster_arn
}

output "redis_auth_secret_arn" {
  description = "ARN of the Redis auth token secret"
  value       = module.redis.auth_secret_arn
}

########################################################
# Cognito Outputs
########################################################

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.cognito.user_pool_id
}

output "cognito_web_client_id" {
  description = "Cognito User Pool Web Client ID"
  value       = module.cognito.web_client_id
}

output "cognito_user_pool_domain" {
  description = "Cognito User Pool Domain"
  value       = module.cognito.user_pool_domain
}

########################################################
# LiteLLM Secrets Outputs
########################################################

output "litellm_secret_arn" {
  description = "ARN of the LiteLLM secret in Secrets Manager"
  value       = module.litellm.litellm_secret_arn
}

output "litellm_secret_name" {
  description = "Name of the LiteLLM secret in Secrets Manager"
  value       = module.litellm.litellm_secret_name
}

########################################################
# Bastion Outputs
########################################################

output "bastion_instance_id" {
  description = "Instance ID of the bastion host"
  value       = module.bastion.bastion_instance_id
}

output "bastion_security_group_id" {
  description = "Security group ID of the bastion host"
  value       = module.bastion.bastion_security_group_id
}

########################################################
# S3 and CloudFront Outputs
########################################################

output "spa_website_bucket_name" {
  description = "Name of the SPA website S3 bucket"
  value       = module.s3_spa_website.bucket_name
}

output "spa_website_url" {
  description = "URL of the SPA website via CloudFront"
  value       = module.cloudfront_spa.spa_website_url
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = module.cloudfront_spa.cloudfront_distribution_id
}

########################################################
# Parameter Store Outputs
########################################################

output "parameter_store_configuration_json" {
  description = "Complete configuration as JSON string"
  value       = module.parameter_store.configuration_json
  sensitive   = true
}

output "parameter_store_name" {
  description = "Name of the parameter store parameter"
  value       = module.parameter_store.parameter_name
}

output "parameter_store_arn" {
  description = "ARN of the parameter store parameter"
  value       = module.parameter_store.parameter_arn
}

########################################################
# General Information
########################################################

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "vpc_id" {
  description = "VPC ID where resources are deployed"
  value       = var.vpc_id
}
