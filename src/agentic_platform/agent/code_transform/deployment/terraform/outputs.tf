output "cluster_name" {
  description = "ECS Cluster Name"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ECS Cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "task_definition_arn" {
  description = "Task Definition ARN"
  value       = aws_ecs_task_definition.atx_test_runner.arn
}

output "task_definition_family" {
  description = "Task Definition Family"
  value       = aws_ecs_task_definition.atx_test_runner.family
}

output "task_role_arn" {
  description = "Task Role ARN"
  value       = aws_iam_role.ecs_task.arn
}

output "execution_role_arn" {
  description = "Execution Role ARN"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "security_group_id" {
  description = "Security Group ID"
  value       = aws_security_group.ecs_tasks.id
}

output "subnet_ids" {
  description = "Public Subnet IDs"
  value       = aws_subnet.public[*].id
}

output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = aws_ecr_repository.atx_test_runner.repository_url
}

output "log_group_name" {
  description = "CloudWatch Log Group Name"
  value       = aws_cloudwatch_log_group.atx_test_runner.name
}

output "run_task_command" {
  description = "AWS CLI command to run the task"
  value = <<-EOT
    aws ecs run-task \
      --cluster ${aws_ecs_cluster.main.name} \
      --task-definition ${aws_ecs_task_definition.atx_test_runner.family} \
      --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[${join(",", aws_subnet.public[*].id)}],securityGroups=[${aws_security_group.ecs_tasks.id}],assignPublicIp=ENABLED}" \
      --region ${var.aws_region}
  EOT
}
