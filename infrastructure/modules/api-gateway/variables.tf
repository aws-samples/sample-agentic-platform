variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "api_name" {
  description = "Name of the API Gateway"
  type        = string
}

variable "description" {
  description = "Description of the API Gateway"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "cognito_user_pool_endpoint" {
  description = "Cognito User Pool endpoint for JWT authorizer (e.g., cognito-idp.us-east-1.amazonaws.com/us-east-1_xxx)"
  type        = string
}

variable "cognito_client_id" {
  description = "Cognito User Pool Client ID for JWT audience validation"
  type        = string
}

variable "cors_allow_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "enable_access_logging" {
  description = "Enable API Gateway access logging to CloudWatch"
  type        = bool
  default     = false
}

variable "access_log_retention_days" {
  description = "CloudWatch log retention for API Gateway access logs"
  type        = number
  default     = 30
}

variable "routes" {
  description = "Map of route key to Lambda integration config. Key is the route (e.g., 'POST /api/invoke')"
  type = map(object({
    lambda_invoke_arn    = string
    lambda_function_name = string
    auth_required        = bool
  }))
  default = {}
}
