########################################################
# Networking Outputs
########################################################

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.networking.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.networking.private_subnet_ids
}

output "public_subnet_1_id" {
  description = "ID of public subnet 1"
  value       = module.networking.public_subnet_1_id
}

output "public_subnet_2_id" {
  description = "ID of public subnet 2"
  value       = module.networking.public_subnet_2_id
}

output "private_subnet_1_id" {
  description = "ID of private subnet 1"
  value       = module.networking.private_subnet_1_id
}

output "private_subnet_2_id" {
  description = "ID of private subnet 2"
  value       = module.networking.private_subnet_2_id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = module.networking.internet_gateway_id
}

output "nat_gateway_1_id" {
  description = "ID of NAT Gateway 1"
  value       = module.networking.nat_gateway_1_id
}

output "nat_gateway_2_id" {
  description = "ID of NAT Gateway 2"
  value       = module.networking.nat_gateway_2_id
}

output "default_security_group_id" {
  description = "ID of the default security group"
  value       = module.networking.default_security_group_id
}

########################################################
# KMS Outputs
########################################################

output "kms_key_id" {
  description = "ID of the KMS key"
  value       = module.kms.kms_key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key"
  value       = module.kms.kms_key_arn
}

output "kms_alias_name" {
  description = "Name of the KMS key alias"
  value       = module.kms.kms_alias_name
}

output "kms_alias_arn" {
  description = "ARN of the KMS key alias"
  value       = module.kms.kms_alias_arn
}

########################################################
# Common Values for Other Stacks
########################################################

output "name_prefix" {
  description = "Common name prefix used by resources"
  value       = local.name_prefix
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}
