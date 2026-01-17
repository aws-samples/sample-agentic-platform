########################################################
# K8s ConfigMap Module Variables
########################################################

variable "cluster_name" {
  description = "Name of the EKS cluster. If empty, no K8s resources are created (optional deployment)"
  type        = string
  default     = ""
}

variable "config_map_name" {
  description = "Name of the ConfigMap to create"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for the ConfigMap"
  type        = string
  default     = "default"
}

variable "configuration_data" {
  description = "Configuration data for the ConfigMap (map of strings)"
  type        = map(string)
}

variable "labels" {
  description = "Labels to apply to the ConfigMap"
  type        = map(string)
  default     = {}
}
