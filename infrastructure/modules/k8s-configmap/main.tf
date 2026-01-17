# K8s ConfigMap Module
#
# Creates Kubernetes ConfigMaps from Terraform
# Only creates resources if cluster_name is provided (optional deployment)
#
# This module is designed to be called from any stack (knowledge-layer, integration-layer, etc.)
# to push configuration into the Kubernetes cluster as ConfigMaps.

terraform {
  required_version = ">= 1.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Only fetch cluster data if cluster_name is provided
data "aws_eks_cluster" "cluster" {
  count = var.cluster_name != "" ? 1 : 0
  name  = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  count = var.cluster_name != "" ? 1 : 0
  name  = var.cluster_name
}

# Configure Kubernetes provider if cluster_name provided
provider "kubernetes" {
  host                   = var.cluster_name != "" ? data.aws_eks_cluster.cluster[0].endpoint : null
  cluster_ca_certificate = var.cluster_name != "" ? base64decode(data.aws_eks_cluster.cluster[0].certificate_authority[0].data) : null
  token                  = var.cluster_name != "" ? data.aws_eks_cluster_auth.cluster[0].token : null
}

# Create ConfigMap only if cluster_name provided
resource "kubernetes_config_map" "config" {
  count = var.cluster_name != "" ? 1 : 0

  metadata {
    name      = var.config_map_name
    namespace = var.namespace
    labels    = var.labels
  }

  data = var.configuration_data
}
