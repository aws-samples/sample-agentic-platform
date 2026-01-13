# EBS CSI Driver addon - managed here since it requires the IRSA role
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name      = var.cluster_name
  addon_name        = "aws-ebs-csi-driver"
  addon_version     = "v1.54.0-eksbuild.1"  # Latest for EKS 1.34
  
  # Link service account - use the IRSA role created in this module
  service_account_role_arn = aws_iam_role.ebs_csi_driver_role.arn
  
  resolve_conflicts_on_update = "PRESERVE"
  
  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi_driver_service_account_policy
  ]
  
  tags = var.common_tags
}
