# -----------------------------------------------------------------------------
# Lambda Function
# -----------------------------------------------------------------------------
output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "Invoke ARN of the Lambda function (for API Gateway integration)"
  value       = aws_lambda_function.this.invoke_arn
}

output "qualified_arn" {
  description = "Qualified ARN of the Lambda function including version"
  value       = aws_lambda_function.this.qualified_arn
}

output "version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.this.version
}

# -----------------------------------------------------------------------------
# IAM Role
# -----------------------------------------------------------------------------
output "role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the Lambda execution IAM role"
  value       = aws_iam_role.this.name
}

output "role_id" {
  description = "ID of the Lambda execution IAM role"
  value       = aws_iam_role.this.id
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------
output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.this.arn
}
