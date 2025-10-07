# – Agent Core Runtime –

variable "create_runtime" {
  description = "Whether or not to create an agent core runtime."
  type        = bool
  default     = false
}

variable "runtime_name" {
  description = "The name of the agent core runtime."
  type        = string
  default     = "TerraformBedrockAgentCoreRuntime"
}

variable "runtime_description" {
  description = "Description of the agent runtime."
  type        = string
  default     = null
}

variable "runtime_role_arn" {
  description = "Optional external IAM role ARN for the Bedrock agent core runtime. If empty, the module will create one internally."
  type        = string
  default     = null
}

variable "runtime_container_uri" {
  description = "The ECR URI of the container for the agent core runtime."
  type        = string
  default     = null
}

variable "runtime_network_mode" {
  description = "Network mode configuration type for the agent core runtime. Valid values: PUBLIC, VPC."
  type        = string
  default     = "PUBLIC"
  
  validation {
    condition     = contains(["PUBLIC", "VPC"], var.runtime_network_mode)
    error_message = "The runtime_network_mode must be either PUBLIC or VPC."
  }
}

variable "runtime_environment_variables" {
  description = "Environment variables for the agent core runtime."
  type        = map(string)
  default     = null
}

variable "runtime_authorizer_configuration" {
  description = "Authorizer configuration for the agent core runtime."
  type = object({
    custom_jwt_authorizer = object({
      allowed_audience = optional(list(string))
      allowed_clients  = optional(list(string))
      discovery_url    = string
    })
  })
  default = null
}

variable "runtime_protocol_configuration" {
  description = "Protocol configuration for the agent core runtime."
  type        = string
  default     = null
}

variable "runtime_tags" {
  description = "A map of tag keys and values for the agent core runtime."
  type        = map(string)
  default     = null
}

# – Agent Core Runtime Endpoint –

variable "create_runtime_endpoint" {
  description = "Whether or not to create an agent core runtime endpoint."
  type        = bool
  default     = false
}

variable "runtime_endpoint_name" {
  description = "The name of the agent core runtime endpoint."
  type        = string
  default     = "TerraformBedrockAgentCoreRuntimeEndpoint"
}

variable "runtime_endpoint_description" {
  description = "Description of the agent core runtime endpoint."
  type        = string
  default     = null
}

variable "runtime_endpoint_agent_runtime_id" {
  description = "The ID of the agent core runtime associated with the endpoint. If not provided, it will use the ID of the agent runtime created by this module."
  type        = string
  default     = null
}

variable "runtime_endpoint_tags" {
  description = "A map of tag keys and values for the agent core runtime endpoint."
  type        = map(string)
  default     = null
}

# - IAM -
variable "permissions_boundary_arn" {
  description = "The ARN of the IAM permission boundary for the role."
  type        = string
  default     = null
}