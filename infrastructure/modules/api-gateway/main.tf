########################################################
# API Gateway HTTP API
########################################################

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name_prefix}${var.api_name}"
  protocol_type = "HTTP"
  description   = var.description

  cors_configuration {
    allow_origins = var.cors_allow_origins
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization", "X-Amz-Date", "X-Api-Key"]
    max_age       = 300
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}${var.api_name}"
  })
}

########################################################
# Cognito JWT Authorizer
########################################################

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.name_prefix}cognito-authorizer"

  jwt_configuration {
    audience = [var.cognito_client_id]
    issuer   = "https://${var.cognito_user_pool_endpoint}"
  }
}

########################################################
# Default Stage with Auto Deploy
########################################################

resource "aws_apigatewayv2_stage" "default" {
  # checkov:skip=CKV_AWS_73:Access logging disabled for sample application
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}${var.api_name}-default-stage"
  })
}

########################################################
# Lambda Integrations
########################################################

resource "aws_apigatewayv2_integration" "lambda" {
  for_each = var.routes

  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = each.value.lambda_invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

########################################################
# Routes
########################################################

resource "aws_apigatewayv2_route" "this" {
  for_each = var.routes

  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.key
  target    = "integrations/${aws_apigatewayv2_integration.lambda[each.key].id}"

  authorization_type = each.value.auth_required ? "JWT" : "NONE"
  authorizer_id      = each.value.auth_required ? aws_apigatewayv2_authorizer.cognito.id : null
}

########################################################
# Lambda Permissions for API Gateway
########################################################

resource "aws_lambda_permission" "apigw" {
  for_each = var.routes

  statement_id  = "AllowAPIGateway-${replace(replace(each.key, " ", "-"), "/", "-")}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
