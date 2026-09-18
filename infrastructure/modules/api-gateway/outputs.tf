########################################################
# API Gateway Outputs
########################################################

output "api_id" {
  description = "ID of the API Gateway"
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "The URI of the API Gateway"
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "api_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "stage_id" {
  description = "ID of the default stage"
  value       = aws_apigatewayv2_stage.default.id
}
