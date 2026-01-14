########################################################
# Cognito User Pool
########################################################

resource "aws_cognito_user_pool" "main" {
  name = "${var.name_prefix}user-pool"
  
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OFF"
  
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
    temporary_password_validity_days = 7
  }
  
  admin_create_user_config {
    allow_admin_create_user_only = true
  }
  
  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "email"
    required                 = true
    
    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }
  
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your verification code"
    email_message        = "Your verification code is {####}"
  }
  
  tags = merge(
    var.common_tags,
    {
      Name = "${var.name_prefix}user-pool"
    }
  )
}

########################################################
# Cognito User Pool Domain
########################################################

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.environment}-auth-${local.suffix}"
  user_pool_id = aws_cognito_user_pool.main.id
}
