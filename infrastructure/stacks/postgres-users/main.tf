# PostgreSQL Users Setup Stack
#
# This stack handles PostgreSQL user and database creation that requires the platform
# infrastructure to be deployed first. It includes:
# - Database user creation for applications
# - Database creation for different services
# - Basic user permissions and access controls
#
# Note: This does NOT handle application-level schema migrations, which are
# managed separately through Alembic. This stack only sets up the foundational
# database infrastructure (users, databases, credentials).
#
# This stack runs after the platform-eks stack and requires connectivity
# to access the private PostgreSQL Aurora cluster.

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = ">= 1.21.0"
    }
  }
}

# Get current region and account data
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Local values
locals {
  common_tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
    Layer       = "postgres-users"
  }
}

########################################################
# Data Sources - Get Platform Configuration
########################################################

# Get platform configuration from parameter store
data "aws_ssm_parameter" "platform_config" {
  name = var.platform_config_parameter_name
}

locals {
  # Parse the platform configuration JSON
  platform_config = jsondecode(data.aws_ssm_parameter.platform_config.value)
}

########################################################
# PostgreSQL Master Credentials
########################################################

# Get PostgreSQL master credentials from Secrets Manager
data "aws_secretsmanager_secret_version" "postgres_master" {
  secret_id = local.platform_config.PG_PASSWORD_SECRET_ARN
}

locals {
  postgres_master_credentials = jsondecode(data.aws_secretsmanager_secret_version.postgres_master.secret_string)
}

########################################################
# PostgreSQL Provider Configuration
########################################################

provider "postgresql" {
  # Use local proxy or direct connection based on variable
  host     = var.use_local_proxy ? "localhost" : local.platform_config.PG_WRITER_ENDPOINT
  port     = var.use_local_proxy ? 5432 : local.platform_config.PG_PORT
  database = local.platform_config.PG_DATABASE
  username = local.postgres_master_credentials.username
  password = local.postgres_master_credentials.password
  sslmode  = var.use_local_proxy ? "disable" : "require"

  # Connection settings
  connect_timeout = 15
  superuser       = false
}

########################################################
# PostgreSQL Administrative Setup
########################################################

module "postgres_admin_setup" {
  source = "../../modules/postgres-admin-setup"

  # Connection configuration
  postgres_host           = local.platform_config.PG_WRITER_ENDPOINT
  postgres_port           = local.platform_config.PG_PORT
  postgres_admin_username = local.postgres_master_credentials.username
  postgres_admin_password = local.postgres_master_credentials.password

  # LiteLLM secret configuration
  litellm_secret_name = local.platform_config.LITELLM_SECRET_NAME

  # AWS configuration for secrets
  name_prefix           = "agentic-platform"
  common_tags           = local.common_tags
  enable_kms_encryption = local.platform_config.KMS_KEY_ARN != null
  kms_key_arn           = local.platform_config.KMS_KEY_ARN
}
