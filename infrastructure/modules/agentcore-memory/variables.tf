# – Agent Core Runtime –

variable "memory_name" {
  description = "The name of the agent core runtime."
  type        = string
}

variable "expiration_duration" {
  description = "Description of the agent runtime."
  type        = number
  default     = 7
}