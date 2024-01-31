output "lb_target_group_id" {
  value       = try(aws_alb_target_group.this[0].id, null)
  description = "ARN of the Target Group."
}

output "name" {
  value       = var.name
  description = "Service name."
}

output "service_id" {
  value       = aws_ecs_service.this.id
  description = "ARN that identifies the service."
}

output "task_role_id" {
  value       = aws_iam_role.task_role.id
  description = "ECS task role ID"
}

output "task_execution_role_id" {
  value       = aws_iam_role.task_execution.id
  description = "ECS task execution role ID"
}

output "deployment_group" {
  value       = aws_iam_group.deployment.name
  description = "Deployment group name"
}

output "deployment_group_arn" {
  value       = aws_iam_group.deployment.arn
  description = "Deployment group ARN"
}
