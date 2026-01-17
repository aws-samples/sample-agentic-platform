########################################################
# K8s ConfigMap Module Outputs
########################################################

output "config_map_name" {
  description = "Name of the created ConfigMap (empty if not created)"
  value       = var.cluster_name != "" ? kubernetes_config_map.config[0].metadata[0].name : ""
}

output "namespace" {
  description = "Namespace of the ConfigMap"
  value       = var.namespace
}

output "created" {
  description = "Whether the ConfigMap was created"
  value       = var.cluster_name != ""
}
