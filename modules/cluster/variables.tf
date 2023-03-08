# required

variable "context" {
  description = "Project context."

  type = object({
    namespace = string
    stage     = string
    name      = string
  })
}

variable "name_prefix" {
  type        = string
  description = "Name prefix (hyphen suffix should be skipped)."
}

variable "vpc_id" {
  type        = string
  description = "AWS VPC id."
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of AWS subent IDs for Autoscaling group."
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type i.e. t3.medium."
}

variable "lb_security_group_id" {
  type        = string
  description = "Load balancer security group id."
}

# optional

variable "autoscaling_group" {
  type = object({
    min_size         = number
    max_size         = number
    desired_capacity = number
  })
  description = "Autoscaling group configuration."
  default = {
    min_size         = 0
    max_size         = 5
    desired_capacity = 0
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags attached to resources."
  default     = {}
}

variable "ssm_tag_key" {
  type        = string
  description = "Tag key to add for SSM access"
  default     = "ssm.group"
}

variable "ssm_tag_value" {
  type        = string
  description = "Tag value to add for SSM access"
  default     = "true"
}

variable "protect_from_scale_in" {
  type        = bool
  description = "If protect from scale in is enabled, newly launched instances will be protected from scale in by default."
  default     = false
}

variable "ami" {
  type        = string
  description = "Image ID for Autoscaling group. If left blank, latest ECS-optimized version will be used."
  default     = ""
}

variable "security_groups" {
  type        = list(string)
  description = "List of security groups attached to launch configuration."
  default     = []
}

variable "cloudinit_parts" {
  type = list(object({
    content      = string
    filename     = string
    content_type = string
  }))
  description = "Parts for cloud-init config that are added to the final MIME document."
  default     = []
}

variable "cloudinit_scripts" {
  type        = list(string)
  description = "Shell scripts added to cloud-init."
  default     = []
}

variable "enable_container_insights" {
  type        = bool
  description = "Enable container insights for the cluster."
  default     = true
}

variable "ecs_loglevel" {
  type        = string
  description = "ECS Cluster log level."
  default     = "info"

  validation {
    condition     = can(regex("^crit|error|warn|info|debug$", var.ecs_loglevel))
    error_message = "The ecs_loglevel must be one of crit, error, warn, info, debug."
  }
}

variable "associate_public_ip_address" {
  type        = bool
  default     = true
  description = "Associate a public ip address with an instance in a VPC."
}

variable "root_block_configuration" {
  type = object({
    volume_type = string
    volume_size = number
  })
  default = {
    volume_type = "gp2"
    volume_size = 30
  }
  description = "Configuration for root block device block."
}

variable "placement_group" {
  description = "Placement group strategy."

  type = object({
    strategy     = string
    spread_level = string
  })
  default = {
    strategy     = "spread"
    spread_level = "rack"
  }
}

variable "allow_ssh" {
  description = "Allow SSH port in SG."
  type        = bool
  default     = false
}

variable "efs" {
  type = object({
    arn = string
  })
  description = "EFS volume to mount to ECS"
  default     = null
}
