# CloudWatch Log Group for EKS Cluster Logs
resource "aws_cloudwatch_log_group" "eks_cluster_logs" {
  # checkov:skip=CKV_AWS_158: KMS encryption is configurable via the enable_kms_encryption variable
  name              = "/aws/eks/${var.name_prefix}eks/cluster"
  retention_in_days = 365
  kms_key_id        = var.enable_kms_encryption ? var.kms_key_arn : null

  tags = var.common_tags
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  # checkov:skip=CKV_AWS_339: This is the latest up to date version of EKS with ADOT support.
  name     = "${var.name_prefix}eks"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.32"

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.eks_cluster_sg.id]
    endpoint_private_access = true
    endpoint_public_access  = var.enable_eks_public_access
  }

  # Enable EKS cluster encryption with KMS only if enable_kms_encryption is true
  dynamic "encryption_config" {
    for_each = var.enable_kms_encryption ? [1] : []
    content {
      provider {
        key_arn = var.kms_key_arn
      }
      resources = ["secrets"]
    }
  }

  # Enable control plane logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Configure access entries authentication mode
  access_config {
    authentication_mode = "API"  # Updated to API-only mode for modern access management
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_service_policy,
    aws_cloudwatch_log_group.eks_cluster_logs
  ]

  tags = merge(
    var.common_tags,
    {
      Environment = var.environment  # Add Environment tag to match IAM policy conditions
    }
  )
}
