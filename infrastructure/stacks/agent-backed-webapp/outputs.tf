########################################################
# CloudFront Outputs
########################################################

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (main entry point)"
  value       = module.cloudfront.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = module.cloudfront.cloudfront_distribution_id
}

output "website_url" {
  description = "URL of the web application"
  value       = "https://${module.cloudfront.cloudfront_domain_name}"
}

########################################################
# API Gateway Outputs
########################################################

output "api_gateway_endpoint" {
  description = "API Gateway endpoint URL"
  value       = module.api_gateway.api_endpoint
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = module.api_gateway.api_id
}

########################################################
# Cognito Outputs
########################################################

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.cognito.user_pool_id
}

output "cognito_web_client_id" {
  description = "Cognito Web Client ID"
  value       = module.cognito.web_client_id
}

output "cognito_auth_url" {
  description = "Cognito authentication URL"
  value       = module.cognito.auth_url
}

########################################################
# S3 Outputs
########################################################

output "frontend_bucket_name" {
  description = "S3 bucket name for frontend assets"
  value       = module.s3_frontend.bucket_name
}

########################################################
# Lambda Outputs
########################################################

output "lambda_function_name" {
  description = "Lambda function name"
  value       = module.lambda_agent_backend.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = module.lambda_agent_backend.function_arn
}
