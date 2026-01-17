terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Get current AWS account and region data
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

########################################################
# Random Suffix for Unique Resource Naming
########################################################

resource "random_string" "suffix" {
  length  = 3
  special = false
  upper   = false
}

########################################################
# Local Values
########################################################

locals {
  name_prefix = var.name_prefix
  suffix      = random_string.suffix.result
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "Agentic Platform - Knowledge Layer"
    Stack       = "knowledge-layer"
  }
}

########################################################
# Knowledge Base Module
########################################################

module "knowledgebase" {
  source = "../../modules/knowledgebase"

  # Core configuration
  name_prefix = local.name_prefix
  common_tags = local.common_tags
  suffix      = local.suffix

  # Region configuration (dynamic)
  aws_region = var.aws_region

  # Knowledge Base configuration
  kb_name          = var.kb_name
  embedding_model  = var.embedding_model
  vector_dimension = var.vector_dimension
  distance_metric  = var.distance_metric

  # KMS encryption (optional)
  enable_kms_encryption = var.enable_kms_encryption
  kms_key_arn           = var.kms_key_arn
}

########################################################
# Parameter Store Configuration
########################################################

module "parameter_store" {
  source = "../../modules/parameter-store"

  # Core configuration
  name_prefix        = local.name_prefix
  common_tags        = local.common_tags
  environment        = var.environment
  aws_region         = var.aws_region
  parameter_base_path = "/knowledge-layer/config"

  # Configuration sections - Knowledge Base only
  configuration_sections = {
    knowledge_base = module.knowledgebase.config
  }
}

########################################################
# Kubernetes ConfigMap (Optional)
########################################################

module "k8s_configmap" {
  source = "../../modules/k8s-configmap"

  # Only create if cluster_name is provided
  cluster_name = var.eks_cluster_name

  # ConfigMap configuration
  config_map_name = "knowledge-layer-config"
  namespace       = "default"

  # Use the configuration from parameter store module
  configuration_data = jsondecode(module.parameter_store.configuration_json)

  labels = {
    "app.kubernetes.io/name"       = "knowledge-layer-config"
    "app.kubernetes.io/component"  = "configuration"
    "app.kubernetes.io/managed-by" = "terraform"
    "layer"                        = "knowledge"
  }
}
