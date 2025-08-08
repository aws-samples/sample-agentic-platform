# Platform Stack
#
# This stack deploys the core platform components that can be deployed
# in any existing VPC infrastructure. Variables are passed in via tfvars
# to make this stack independent and reusable.
#
# Components included:
# - EKS cluster with managed node groups
# - IRSA roles for service accounts
# - PostgreSQL Aurora cluster (future)
# - Bastion host for VPC access (future)

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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
}

# Configure Kubernetes provider using EKS module outputs
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.main.token
}

# Get EKS cluster auth token
data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
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
    Environment = "dev"
    ManagedBy   = "Terraform"
    Project     = "Agentic Platform Sample"
  }
}

########################################################
# EKS Cluster
########################################################

module "eks" {
  source = "../../modules/eks"

  # Core configuration
  name_prefix  = local.name_prefix
  common_tags  = local.common_tags
  environment  = var.environment

  # Networking - passed in as variables
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  # KMS encryption - passed in as variables
  enable_kms_encryption = var.enable_kms_encryption
  kms_key_arn          = var.kms_key_arn

  # Enable public access to cluster. 
  enable_eks_public_access = var.enable_eks_public_access

  # Node configuration
  node_instance_types = var.node_instance_types
  node_scaling_config = var.node_scaling_config
  node_disk_size     = var.node_disk_size

  # Additional admin access
  additional_admin_role_arns = var.additional_admin_role_arns

  # Security group access
  bastion_security_group_ids = [module.bastion.bastion_security_group_id]
  bastion_iam_role_arns      = [module.bastion.bastion_iam_role_arn]
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

  # Security - allow access from EKS nodes and bastion
  eks_node_security_group_ids = [module.eks.node_security_group_id]
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
# IRSA Roles for Service Accounts
########################################################

module "irsa" {
  source = "../../modules/irsa"

  # Core configuration
  name_prefix = local.name_prefix
  common_tags = local.common_tags

  # EKS cluster configuration
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  cluster_name           = module.eks.cluster_name

  # Resource ARNs for service access
  redis_cluster_arns     = [module.redis.cluster_arn]
  redis_secret_arns      = [module.redis.auth_secret_arn]
  postgres_secret_arns   = [module.postgres_aurora.master_user_secret_arn]
  postgres_db_user_arns  = [module.postgres_aurora.rds_connect_policy_arn]
  secrets_manager_arns   = [module.cognito.m2m_credentials_secret_arn]
  
  # LiteLLM specific ARNs
  litellm_secret_arns           = [module.litellm.litellm_secret_arn]
  litellm_postgres_db_user_arns = [module.litellm.postgres_db_user_arn]
  
  # Agent specific ARNs
  agent_secret_arns = [module.litellm.agent_secret_arn]

  # Fix chicken and egg problem: EBS CSI addon needs nodes to be ready
  depends_on = [module.eks]
}

########################################################
# LiteLLM AI Model Proxy
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

  # EKS configuration
  eks_cluster_name = module.eks.cluster_name
  eks_cluster_arn  = module.eks.cluster_arn

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
    eks        = module.eks.config,
    cognito    = module.cognito.config,
    postgres   = module.postgres_aurora.config,
    redis      = module.redis.config,
    litellm    = module.litellm.config,
    irsa       = module.irsa.config,
    bastion    = module.bastion.config,
    s3         = {
      SPA_WEBSITE_BUCKET_NAME = module.s3_spa_website.bucket_name
      SPA_WEBSITE_BUCKET_ARN  = module.s3_spa_website.bucket_arn
    },
    cloudfront = {
      SPA_DISTRIBUTION_ID     = module.cloudfront_spa.cloudfront_distribution_id
      SPA_DISTRIBUTION_ARN    = module.cloudfront_spa.cloudfront_distribution_arn
      SPA_DOMAIN_NAME        = module.cloudfront_spa.cloudfront_domain_name
      SPA_WEBSITE_URL        = module.cloudfront_spa.spa_website_url
    },
    
    # Comment out knowledge base for now
    # knowledge_base = {
    #   KNOWLEDGE_BASE_ID = module.bedrock.default_kb_identifier
    # }
  }
}

########################################################
# Conditional Kubernetes Module
########################################################

module "kubernetes" {
  count = (var.enable_eks_public_access && !var.deploy_inside_vpc) || (!var.enable_eks_public_access && var.deploy_inside_vpc) ? 1 : 0
  
  source = "../../modules/kubernetes"

  # ConfigMap configuration - use the parsed JSON from parameter store
  namespace          = "default"
  configuration_data = jsondecode(module.parameter_store.configuration_json)

  # External Secrets Operator configuration
  external_secrets_service_account_role_arn = module.irsa.external_secrets_role_arn

  # AWS Load Balancer Controller configuration
  aws_load_balancer_controller_service_account_role_arn = module.irsa.load_balancer_controller_role_arn
  cluster_name                                          = module.eks.cluster_name
  aws_region                                            = var.aws_region
  vpc_id                                                = var.vpc_id

  # OTEL Collectors configuration
  otel_chart_path         = "../../../k8s/helm/charts/otel"
  otel_collector_role_arn = module.irsa.otel_collector_role_arn

  # Ensure kubernetes module waits for EKS and IRSA to be ready
  depends_on = [module.eks, module.irsa]
}
