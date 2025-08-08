variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where EKS cluster will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS cluster and nodes"
  type        = list(string)
}

variable "enable_kms_encryption" {
  description = "Enable KMS encryption for EKS secrets and EBS volumes"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "ARN of the KMS key to use for encryption"
  type        = string
  default     = null
}

variable "enable_eks_public_access" {
  description = "Enable public access to the EKS cluster"
  type        = bool
  default     = false
}

variable "additional_admin_role_arns" {
  description = "List of additional IAM role ARNs to grant cluster admin access"
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  description = "List of instance types for EKS worker nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_scaling_config" {
  description = "Scaling configuration for EKS node group"
  type = object({
    desired_size = number
    max_size     = number
    min_size     = number
  })
  default = {
    desired_size = 4
    max_size     = 6
    min_size     = 2
  }
}

variable "node_disk_size" {
  description = "Disk size in GB for EKS worker nodes"
  type        = number
  default     = 20
}

########################################################
# Security Group Variables
########################################################

variable "bastion_security_group_ids" {
  description = "List of bastion host security group IDs that need access to EKS"
  type        = list(string)
  default     = []
}

variable "bastion_iam_role_arns" {
  description = "List of bastion host IAM role ARNs that need access to EKS"
  type        = list(string)
  default     = []
}
