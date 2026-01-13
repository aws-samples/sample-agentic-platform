# EKS Addons - Required for node groups to join the cluster
resource "aws_eks_addon" "vpc_cni" {
  cluster_name    = aws_eks_cluster.main.name
  addon_name      = "vpc-cni"
  addon_version   = "v1.21.1-eksbuild.1"  # Latest for EKS 1.34
  
  resolve_conflicts_on_update = "OVERWRITE"
  
  depends_on = [
    aws_eks_cluster.main
  ]
}

resource "aws_eks_addon" "coredns" {
  cluster_name    = aws_eks_cluster.main.name
  addon_name      = "coredns"
  addon_version   = "v1.12.4-eksbuild.1"  # Latest for EKS 1.34
  
  resolve_conflicts_on_update = "OVERWRITE"
  
  # CoreDNS requires nodes to be available
  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main
  ]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name    = aws_eks_cluster.main.name
  addon_name      = "kube-proxy"
  addon_version   = "v1.34.0-eksbuild.2"  # Default for EKS 1.34
  
  resolve_conflicts_on_update = "OVERWRITE"
  
  depends_on = [
    aws_eks_cluster.main
  ]
}

# Add cert-manager addon (required for ADOT)
resource "aws_eks_addon" "cert_manager" {
  cluster_name      = aws_eks_cluster.main.name
  addon_name        = "cert-manager"
  addon_version     = "v1.17.2-eksbuild.1"  # Compatible with EKS 1.34
  
  resolve_conflicts_on_update = "OVERWRITE"
  
  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main
  ]
  
  tags = var.common_tags
}

# Add AWS Distro for OpenTelemetry (ADOT) addon
resource "aws_eks_addon" "adot" {
  cluster_name      = aws_eks_cluster.main.name
  addon_name        = "adot"
  addon_version     = "v0.141.0-eksbuild.1"  # Default for EKS 1.34
  
  # Use PRESERVE to maintain any custom configurations
  resolve_conflicts_on_update = "PRESERVE"
  
  # ADOT requires cert-manager to be installed first
  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main,
    aws_eks_addon.cert_manager  # Make sure cert-manager is installed first
  ]
  
  tags = var.common_tags
}

# Note: EBS CSI Driver addon is now managed by the IRSA module
# since it requires the IRSA role to be created first
