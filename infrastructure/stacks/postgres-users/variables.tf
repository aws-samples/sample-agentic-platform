########################################################
# Core Variables
########################################################

variable "platform_config_parameter_name" {
  description = "Name of the SSM parameter containing platform configuration"
  type        = string
  default     = "/agentic-platform/config/dev"
}

variable "use_local_proxy" {
  description = "Use local proxy (localhost) instead of direct PostgreSQL connection"
  type        = bool
  default     = false
}
