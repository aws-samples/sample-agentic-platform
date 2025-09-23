# ECS LiteLLM Module Outputs

########################################################
# ECS Cluster Outputs
########################################################

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

########################################################
# ECS Service Outputs
########################################################

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.litellm.name
}

output "service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.litellm.id
}

output "task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.litellm.arn
}

########################################################
# Load Balancer Outputs
########################################################

output "load_balancer_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.litellm.arn
}

########################################################
# Security Group Outputs
########################################################

output "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs_tasks.id
}

output "alb_security_group_id" {
  description = "Security group ID for Application Load Balancer"
  value       = aws_security_group.alb.id
}

########################################################
# IAM Role Outputs
########################################################

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task.arn
}

########################################################
# CloudWatch Log Group Outputs
########################################################

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.litellm.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.litellm.arn
}

########################################################
# Structured Configuration (for Parameter Store)
########################################################

output "config" {
  description = "Complete ECS LiteLLM configuration for parameter store"
  value = {
    # ECS Configuration
    ECS_CLUSTER_NAME     = aws_ecs_cluster.main.name
    ECS_CLUSTER_ARN      = aws_ecs_cluster.main.arn
    ECS_SERVICE_NAME     = aws_ecs_service.litellm.name
    ECS_SERVICE_ARN      = aws_ecs_service.litellm.id
    
    # Load Balancer Configuration
    LITELLM_LOAD_BALANCER_DNS = aws_lb.main.dns_name
    LITELLM_URL              = "http://${aws_lb.main.dns_name}"
    TARGET_GROUP_ARN         = aws_lb_target_group.litellm.arn
    
    # Security Groups
    ECS_SECURITY_GROUP_ID = aws_security_group.ecs_tasks.id
    ALB_SECURITY_GROUP_ID = aws_security_group.alb.id
    
    # IAM Roles
    ECS_TASK_EXECUTION_ROLE_ARN = aws_iam_role.ecs_task_execution.arn
    ECS_TASK_ROLE_ARN          = aws_iam_role.ecs_task.arn
    
    # Logging
    LOG_GROUP_NAME = aws_cloudwatch_log_group.litellm.name
  }
}
