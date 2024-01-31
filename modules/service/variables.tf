# required

variable "context" {
  description = "Project context."

  type = object({
    namespace = string
    stage     = string
    name      = string
  })
}

variable "vpc_id" {
  type        = string
  description = "VPC id."
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of AWS subent IDs for service."
}

variable "name" {
  type        = string
  description = "ECS Service name."
}

variable "cluster_id" {
  type        = string
  description = "ECS Cluster id."
}

variable "desired_count" {
  type        = number
  description = "Desired task count."
}

# optional

variable "port" {
  description = "Container port"
  type        = number
  default     = null
}

variable "enable_execute_command" {
  description = "Allow to exec into containers."
  type        = bool
  default     = true
}

variable "create_alb_target_group" {
  description = "Register service as targer for load balancer."
  type        = bool
  default     = true
}

variable "secrets" {
  description = "Paths to secret. All secrets are read under the path."
  type        = set(string)
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Additional tags attached to resources."
  default     = {}
}

variable "one_off_commands" {
  type        = set(string)
  description = "Set of commands that the tasks are created for."
  default     = []
}

variable "health_check" {
  type = object({
    path    = string
    matcher = string
  })
  description = "Health check config for ALB target group."
  default = {
    path    = "/"
    matcher = "200"
  }
}

variable "health_check_threshold" {
  type = object({
    timeout   = number
    interval  = number
    healthy   = number
    unhealthy = number
  })
  description = "Health check thresholds for ALB target group."
  default = {
    timeout   = 10
    interval  = 15
    healthy   = 3
    unhealthy = 3
  }
}

variable "deregistration_delay" {
  description = "Deregistration delay (draining time) from LB."

  type    = number
  default = 30
}

variable "deployment_minimum_healthy_percent" {
  description = "Lower limit (as a percentage of the service's desiredCount) of the number of running tasks that must remain running and healthy in a service during a deployment."

  type    = number
  default = 50
}

variable "deployment_maximum_percent" {
  description = "Upper limit (as a percentage of the service's `desired_count`) of the number of running tasks that can be running in a service during a deployment. Not valid when using the `DAEMON` scheduling strategy."

  type    = number
  default = 200
}

variable "log_retention_in_days" {
  type        = string
  description = "Log retention in days for Cloudwatch."
  default     = 365
}

variable "efs" {
  type = object({
    id         = string
    mount_path = string
    volume     = string
  })
  description = "EFS volume to mount to ECS"
  default     = null
}
