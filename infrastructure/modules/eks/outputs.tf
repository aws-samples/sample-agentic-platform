########################################################
# EKS Cluster Outputs
########################################################

output "cluster_id" {
  description = "Name/ID of the EKS cluster"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_platform_version" {
  description = "Platform version for the EKS cluster"
  value       = aws_eks_cluster.main.platform_version
}

output "cluster_status" {
  description = "Status of the EKS cluster"
  value       = aws_eks_cluster.main.status
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

########################################################
# EKS Node Group Outputs
########################################################

output "node_group_arn" {
  description = "ARN of the EKS node group"
  value       = aws_eks_node_group.main.arn
}

output "node_group_status" {
  description = "Status of the EKS node group"
  value       = aws_eks_node_group.main.status
}

output "node_group_capacity_type" {
  description = "Type of capacity associated with the EKS node group"
  value       = aws_eks_node_group.main.capacity_type
}

output "node_group_instance_types" {
  description = "Instance types associated with the EKS node group"
  value       = aws_eks_node_group.main.instance_types
}

########################################################
# IAM Role Outputs
########################################################

output "cluster_iam_role_name" {
  description = "IAM role name associated with EKS cluster"
  value       = aws_iam_role.eks_cluster_role.name
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN associated with EKS cluster"
  value       = aws_iam_role.eks_cluster_role.arn
}

output "node_group_iam_role_name" {
  description = "IAM role name associated with EKS node group"
  value       = aws_iam_role.eks_node_role.name
}

output "node_group_iam_role_arn" {
  description = "IAM role ARN associated with EKS node group"
  value       = aws_iam_role.eks_node_role.arn
}

output "deployment_role_arn" {
  description = "IAM role ARN for EKS deployment operations"
  value       = aws_iam_role.eks_deployment_role.arn
}

########################################################
# Security Group Outputs
########################################################

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.eks_cluster_sg.id
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS node group"
  value       = aws_security_group.eks_nodes_sg.id
}

########################################################
# OIDC Provider Outputs
########################################################

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

########################################################
# CloudWatch Outputs
########################################################

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for EKS cluster logs"
  value       = aws_cloudwatch_log_group.eks_cluster_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for EKS cluster logs"
  value       = aws_cloudwatch_log_group.eks_cluster_logs.arn
}

########################################################
# Structured Configuration (for Parameter Store)
########################################################

output "config" {
  description = "Complete EKS configuration for parameter store"
  value = {
    # EKS Cluster
    EKS_CLUSTER_NAME     = aws_eks_cluster.main.name
    EKS_CLUSTER_ID       = aws_eks_cluster.main.id
    EKS_CLUSTER_ENDPOINT = aws_eks_cluster.main.endpoint
    EKS_NODE_GROUP_ID    = aws_eks_node_group.main.id
    CLUSTER_NAME         = aws_eks_cluster.main.name
  }
}
output "cluster_oidc_provider_arn" {
  description = "The ARN of the OIDC Identity Provider for the EKS cluster"
  value       = aws_iam_openid_connect_provider.eks.arn
}

########################################################
# Access Entries Outputs
########################################################

output "access_entries_ready" {
  description = "Indicates when all access entries and policies are ready"
  value = "ready"
  depends_on = [
    aws_eks_access_entry.cluster_admin,
    aws_eks_access_policy_association.cluster_admin_policy,
    aws_eks_access_entry.additional_admins,
    aws_eks_access_policy_association.additional_admins_policy,
    aws_eks_access_entry.bastion_hosts,
    aws_eks_access_policy_association.bastion_hosts_policy
  ]
}
