output "lb_target_group_id" {
  value       = aws_alb_target_group.this.id
  description = "ARN of the Target Group."
}

output "service_id" {
  value       = aws_ecs_service.this.id
  description = "ARN that identifies the service."
}

output "task_definition" {
  value       = local.task_definition
  description = "Latest task definition (family:revision)."
}

output "task_family" {
  value       = aws_ecs_task_definition.this.family
  description = "ECS task family."
}

output "task_role_id" {
  value       = aws_iam_role.task_role.id
  description = "ECS task role ID"
}

output "task_execution_role_id" {
  value       = aws_iam_role.task_execution.id
  description = "ECS task role ID"
}

output "deployment_policy_id" {
  value       = aws_iam_policy.pass_role.id
  description = "Policy for ECS deployment"
}
