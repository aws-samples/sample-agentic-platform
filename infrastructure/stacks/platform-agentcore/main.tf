# Platform AgentCore Stack
#
# This stack deploys a "lite" version of the agentic platform using ECS instead of EKS.
# It reuses foundation components (VPC, Cognito, PostgreSQL, ElastiCache, Bastion) 
# and adds ECS-specific components for running LiteLLM as a containerized service.
#
# Components included:
# - ECS cluster with Fargate capacity
# - ECR repository for LiteLLM container images
# - ECS service and task definition for LiteLLM
# - Application Load Balancer for LiteLLM
# - IAM roles and policies for ECS tasks
# - PostgreSQL Aurora cluster
# - ElastiCache Redis cluster
# - Cognito authentication
# - Bastion host for VPC access

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
}

# Get current AWS account information
data "aws_caller_identity" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 3
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  name_prefix = var.name_prefix
  suffix      = random_string.suffix.result
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "Agentic Platform Sample - AgentCore"
  }
}

########################################################
# PostgreSQL Aurora Cluster
########################################################

module "postgres_aurora" {
  source = "../../modules/postgres-aurora"

  # Core configuration
  name_prefix = local.name_prefix
  common_tags = local.common_tags
  suffix      = local.suffix

  # Networking - passed in as variables
  vpc_id                = var.vpc_id
  vpc_cidr_block       = var.vpc_cidr_block
  private_subnet_ids   = var.private_subnet_ids

  # Security - allow access from ECS tasks and bastion
  eks_node_security_group_ids = [module.ecs_litellm.ecs_security_group_id]
  bastion_security_group_ids  = [module.bastion.bastion_security_group_id]

  # Database configuration
  instance_count                = var.postgres_instance_count
  instance_class               = var.postgres_instance_class
  postgres_deletion_protection = var.postgres_deletion_protection
  postgres_iam_username        = var.postgres_iam_username

  # KMS encryption - passed in as variables
  enable_kms_encryption = var.enable_kms_encryption
  kms_key_arn          = var.kms_key_arn
  kms_key_id           = var.kms_key_id
}

########################################################
#  Cache (Redis ElastiCache)
########################################################

module "redis" {
  source = "../../modules/elasticache"

  # Core configuration
  name_prefix = local.name_prefix
  common_tags = local.common_tags
  suffix      = local.suffix

  # Cache naming
  cache_name    = "redis"
  cache_purpose = "agentic platform caching"

  # Networking - passed in as variables
  vpc_id             = var.vpc_id
  vpc_cidr_block     = var.vpc_cidr_block
  private_subnet_ids = var.private_subnet_ids

  # Redis configuration
  node_type                 = var.redis_node_type
  engine_version           = var.redis_engine_version
  num_cache_clusters       = var.redis_num_cache_clusters
  maintenance_window       = var.redis_maintenance_window
  snapshot_window          = var.redis_snapshot_window
  snapshot_retention_limit = var.redis_snapshot_retention_limit

  # KMS encryption - passed in as variables
  enable_kms_encryption = var.enable_kms_encryption
  kms_key_arn          = var.kms_key_arn
}

########################################################
# Cognito Authentication
########################################################

module "cognito" {
  source = "../../modules/cognito"

  # Core configuration
  name_prefix = local.name_prefix
  common_tags = local.common_tags
  environment = var.environment

  # Cognito-specific configuration
  domain_name               = var.domain_name
  use_custom_domain        = var.use_custom_domain
  enable_federated_identity = var.enable_federated_identity
  enable_kms_encryption    = var.enable_kms_encryption
  kms_key_arn             = var.kms_key_arn
}

########################################################
# LiteLLM AI Model Proxy (Secrets Management)
########################################################

module "litellm" {
  source = "../../modules/litellm"

  # Core configuration
  name_prefix = local.name_prefix
  common_tags = local.common_tags

  # PostgreSQL configuration
  postgres_endpoint            = module.postgres_aurora.cluster_endpoint
  postgres_port               = module.postgres_aurora.cluster_port
  postgres_cluster_resource_id = module.postgres_aurora.cluster_resource_id
  postgres_iam_username       = "litellm"

  # Redis configuration
  redis_endpoint   = module.redis.primary_endpoint_address
  redis_auth_token = module.redis.auth_token

  # KMS encryption
  enable_kms_encryption = var.enable_kms_encryption
  kms_key_arn          = var.kms_key_arn
}

########################################################
# ECS LiteLLM Service
########################################################

module "ecs_litellm" {
  source = "../../modules/ecs"

  # Core configuration
  name_prefix = local.name_prefix
  common_tags = local.common_tags
  suffix      = local.suffix

  # Networking
  vpc_id             = var.vpc_id
  vpc_cidr_block     = var.vpc_cidr_block
  private_subnet_ids = var.private_subnet_ids
  public_subnet_ids  = var.public_subnet_ids

  # LiteLLM configuration
  litellm_secret_arn = module.litellm.litellm_secret_arn
  
  # PostgreSQL access
  postgres_cluster_resource_id = module.postgres_aurora.cluster_resource_id
  postgres_cluster_endpoint    = module.postgres_aurora.cluster_endpoint
  postgres_secret_arn         = module.postgres_aurora.master_user_secret_arn

  # Redis access
  redis_cluster_arn   = module.redis.cluster_arn
  redis_secret_arn    = module.redis.auth_secret_arn

  # ECS configuration
  cpu                    = var.litellm_cpu
  memory                = var.litellm_memory
  desired_count         = var.litellm_desired_count
  enable_auto_scaling   = var.litellm_enable_auto_scaling
  min_capacity          = var.litellm_min_capacity
  max_capacity          = var.litellm_max_capacity

  # KMS encryption
  enable_kms_encryption = var.enable_kms_encryption
  kms_key_arn          = var.kms_key_arn
}

########################################################
# Bastion Host for VPC Access
########################################################

module "bastion" {
  source = "../../modules/bastion"

  # Core configuration
  name_prefix = local.name_prefix
  common_tags = local.common_tags

  # Networking
  vpc_id            = var.vpc_id
  private_subnet_id = var.private_subnet_ids[0]  # Use first private subnet

  # EKS configuration (not applicable for ECS, but keeping for compatibility)
  eks_cluster_name = "dummy-cluster"  # Placeholder since bastion module requires it
  eks_cluster_arn  = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/dummy-cluster"

  # RDS configuration
  rds_cluster_resource_id = module.postgres_aurora.cluster_resource_id

  # Redis configuration
  redis_cluster_arn = module.redis.cluster_arn

  # Secrets Manager ARNs
  secrets_manager_arns = [
    module.postgres_aurora.master_user_secret_arn,
    module.redis.auth_secret_arn,
    module.cognito.m2m_credentials_secret_arn,
    module.litellm.litellm_secret_arn
  ]
}

########################################################
# S3 Bucket for SPA Website
########################################################

module "s3_spa_website" {
  source = "../../modules/s3"

  # Core configuration
  bucket_type = "StaticWebsite"
  common_tags = local.common_tags

  # Website-specific configuration
  force_destroy                  = var.s3_force_destroy
  enable_cloudfront_oac_policy   = true
  cloudfront_distribution_arn    = module.cloudfront_spa.cloudfront_distribution_arn
  
  # Lifecycle configuration for cleanup
  enable_lifecycle_configuration = true
  lifecycle_rules = [
    {
      id                              = "spa_website_lifecycle"
      status                         = "Enabled"
      filter_prefix                  = ""
      abort_incomplete_multipart_days = 7
    }
  ]
}

########################################################
# CloudFront Distribution for SPA Website
########################################################

module "cloudfront_spa" {
  source = "../../modules/cloudfront"

  # Core configuration
  name_prefix = local.name_prefix
  suffix      = local.suffix
  common_tags = local.common_tags
  environment = var.environment

  # S3 bucket configuration
  s3_bucket_name                  = module.s3_spa_website.bucket_name
  s3_bucket_regional_domain_name  = module.s3_spa_website.bucket_regional_domain_name

  # VPC origins configuration
  vpc_origin_arns = [module.ecs_litellm.load_balancer_arn]
}

########################################################
# Parameter Store Configuration
########################################################

module "parameter_store" {
  source = "../../modules/parameter-store"

  # Core configuration
  name_prefix     = local.name_prefix
  common_tags     = local.common_tags
  environment     = var.environment
  aws_region      = var.aws_region
  parameter_name  = "/agentic-platform/config/agentcore-${var.environment}"

  # Configuration sections from each module
  configuration_sections = {
    # Infrastructure values (platform-level)
    infrastructure = {
      VPC_ID             = var.vpc_id
      AWS_DEFAULT_REGION = var.aws_region
      AWS_ACCOUNT_ID     = data.aws_caller_identity.current.account_id
      ENVIRONMENT        = var.environment
      REGION             = var.aws_region
      # Add KMS values if enabled
      KMS_KEY_ARN        = var.enable_kms_encryption ? var.kms_key_arn : null
      KMS_KEY_ID         = var.enable_kms_encryption ? var.kms_key_id : null
    },
    
    # Module configurations (each module gets its own section)
    ecs_litellm = module.ecs_litellm.config,
    cognito     = module.cognito.config,
    postgres    = module.postgres_aurora.config,
    redis       = module.redis.config,
    litellm     = module.litellm.config,
    bastion     = module.bastion.config,
    s3          = {
      SPA_WEBSITE_BUCKET_NAME = module.s3_spa_website.bucket_name
      SPA_WEBSITE_BUCKET_ARN  = module.s3_spa_website.bucket_arn
    },
    cloudfront = {
      SPA_DISTRIBUTION_ID     = module.cloudfront_spa.cloudfront_distribution_id
      SPA_DISTRIBUTION_ARN    = module.cloudfront_spa.cloudfront_distribution_arn
      SPA_DOMAIN_NAME        = module.cloudfront_spa.cloudfront_domain_name
      SPA_WEBSITE_URL        = module.cloudfront_spa.spa_website_url
    }
  }
}
