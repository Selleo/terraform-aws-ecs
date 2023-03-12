data "aws_region" "this" {}
data "aws_caller_identity" "this" {}

locals {
  tags = merge({
    "terraform.module"    = "Selleo/terraform-aws-ecs"
    "terraform.submodule" = "service"
    "context.namespace"   = var.context.namespace
    "context.stage"       = var.context.stage
    "context.name"        = var.context.name
  }, var.tags)

  task_definition = "${aws_ecs_task_definition.this.family}:${max(
    aws_ecs_task_definition.this.revision,
    data.aws_ecs_task_definition.this.revision,
  )}"

  container_definition_overrides = {
    command = var.command
  }

  secrets_kv = [
    for each_secret in data.aws_ssm_parameters_by_path.secrets :
    zipmap(each_secret.names, each_secret.arns)
  ]

  secrets = flatten([
    for secrets_kv in local.secrets_kv : [
      for k, v in secrets_kv : {
        name      = reverse(split("/", k))[0]
        valueFrom = v
      }
    ]
  ])

  ordered_placement_strategy = [
    {
      type  = "spread"
      field = "attribute:ecs.avaiability-zones"
    },
    {
      type  = "spread"
      field = "instanceId"
    }
  ]
}

resource "random_id" "prefix" {
  byte_length = 4
  prefix      = "${var.name}-"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "${var.context.namespace}/${var.context.stage}/${var.context.name}/ecs/${var.name}"
  retention_in_days = var.log_retention_in_days

  tags = merge(local.tags, { "resource.group" = "log" })
}

resource "aws_cloudwatch_log_group" "one_off" {
  for_each = var.one_off_commands

  name              = "${var.context.namespace}/${var.context.stage}/${var.context.name}/ecs/${var.name}-${each.key}"
  retention_in_days = var.log_retention_in_days

  tags = merge(local.tags, { "resource.group" = "log" })
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  network_mode             = var.fargate ? "awsvpc" : "bridge"
  requires_compatibilities = var.fargate ? ["FARGATE"] : ["EC2"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task_role.arn

  cpu    = var.limits.cpu
  memory = var.limits.mem_max

  container_definitions = jsonencode(
    [
      merge({
        essential         = true,
        memoryReservation = var.limits.mem_min,
        memory            = var.limits.mem_max,
        cpu               = var.limits.cpu,
        name              = var.name,
        image             = var.image,
        mountPoints = var.efs == null ? [] : [
          {
            sourceVolume  = var.efs.volume
            containerPath = var.efs.mount_path
            readOnly      = false
          }
        ],
        volumesFrom = [],
        portMappings = [
          {
            containerPort = var.port.container,
            hostPort      = var.port.host, # fargate port must match container port
            protocol      = "tcp",
          },
        ],

        environment = [
          for k, v in var.envs :
          {
            name  = k
            value = v
          }
        ],

        secrets = local.secrets,

        logConfiguration = {
          logDriver = "awslogs",
          options = {
            awslogs-group         = aws_cloudwatch_log_group.this.name,
            awslogs-region        = data.aws_region.this.name,
            awslogs-stream-prefix = "ecs",
          },
        },
      }, length(var.command) == 0 ? {} : local.container_definition_overrides) # merge only if command not empty
  ])

  dynamic "volume" {
    for_each = var.efs == null ? [] : [var.efs.volume]

    content {
      name = var.efs.volume

      efs_volume_configuration {
        file_system_id = var.efs.id
        root_directory = "/"
        # transit_encryption      = "ENABLED"
        # transit_encryption_port = 2999
      }
    }
  }

  tags = merge(local.tags, { "resource.group" = "compute" })
}

resource "aws_ecs_task_definition" "one_off" {
  for_each = var.one_off_commands

  family                   = "${var.name}-${each.key}"
  network_mode             = var.fargate ? "awsvpc" : "bridge"
  requires_compatibilities = var.fargate ? ["FARGATE"] : ["EC2"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task_role.arn

  cpu    = var.limits.cpu
  memory = var.limits.mem_max

  container_definitions = jsonencode(
    [
      {
        command           = [each.key]
        essential         = true,
        memoryReservation = var.limits.mem_min,
        memory            = var.limits.mem_max,
        cpu               = var.limits.cpu,
        name              = var.name,
        image             = var.image,
        mountPoints = var.efs == null ? [] : [
          {
            sourceVolume  = var.efs.volume
            containerPath = var.efs.mount_path
            readOnly      = false
          }
        ],
        volumesFrom  = [],
        portMappings = [],

        environment = [
          for k, v in var.envs :
          {
            name  = k
            value = v
          }
        ],

        secrets = local.secrets,

        logConfiguration = {
          logDriver = "awslogs",
          options = {
            awslogs-group         = aws_cloudwatch_log_group.one_off[each.key].name,
            awslogs-region        = data.aws_region.this.name,
            awslogs-stream-prefix = "ecs",
          },
        },
      }
  ])

  dynamic "volume" {
    for_each = var.efs == null ? [] : [var.efs.volume]

    content {
      name = var.efs.volume

      efs_volume_configuration {
        file_system_id = var.efs.id
        root_directory = "/"
        # transit_encryption      = "ENABLED"
        # transit_encryption_port = 2999
      }
    }
  }

  tags = merge(local.tags, { "resource.group" = "compute" })
}

data "aws_ecs_task_definition" "this" {
  task_definition = aws_ecs_task_definition.this.family
  depends_on      = [aws_ecs_task_definition.this]
}

resource "aws_security_group" "this" {
  name   = "${random_id.prefix.hex}-ecs-tasks"
  vpc_id = var.vpc_id

  tags = merge(local.tags, { "resource.group" = "network" })
}


# needed by fargate
resource "aws_security_group_rule" "egress" {
  count = var.fargate ? 1 : 0

  security_group_id = aws_security_group.this.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

# needed by fargate
resource "aws_security_group_rule" "ingress" {
  count = var.fargate ? 1 : 0

  security_group_id = aws_security_group.this.id
  type              = "ingress"
  from_port         = var.port.container
  to_port           = var.port.container
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_id
  task_definition = local.task_definition

  launch_type = var.fargate ? "FARGATE" : "EC2"

  dynamic "load_balancer" {
    for_each = var.create_alb_target_group ? [1] : []

    content {
      target_group_arn = aws_alb_target_group.this[0].arn
      container_name   = var.name
      container_port   = var.port.container
    }
  }

  dynamic "network_configuration" {
    for_each = var.fargate ? [1] : []

    content {
      security_groups  = [aws_security_group.this.id]
      subnets          = var.subnet_ids
      assign_public_ip = true
    }
  }

  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  dynamic "ordered_placement_strategy" {
    for_each = var.fargate ? [] : local.ordered_placement_strategy

    content {
      type  = ordered_placement_strategy.value.type
      field = ordered_placement_strategy.value.field
    }
  }

  tags = merge(local.tags, { "resource.group" = "compute" })
}

resource "aws_iam_role" "task_role" {
  name = "${random_id.prefix.hex}-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })

  tags = merge(local.tags, { "resource.group" = "identity" })
}


resource "aws_iam_role" "task_execution" {
  name = "${random_id.prefix.hex}-task-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })

  tags = merge(local.tags, { "resource.group" = "identity" })
}

resource "aws_iam_role_policy" "task_execution" {
  name   = "${random_id.prefix.hex}-task-execution"
  role   = aws_iam_role.task_execution.name
  policy = data.aws_iam_policy_document.task_execution.json
}

resource "aws_iam_role_policy" "ssm_get" {
  count = length(var.secrets) == 0 ? 0 : 1

  name   = "${random_id.prefix.hex}-ssm-get"
  role   = aws_iam_role.task_execution.name
  policy = data.aws_iam_policy_document.task_execution_ssm_get.json
}

data "aws_iam_policy_document" "task_execution_ssm_get" {
  statement {
    sid    = "GetSSMParams"
    effect = "Allow"
    actions = [
      "ssm:GetParameters",
    ]

    resources = [
      for secret in var.secrets :
      "arn:aws:ssm:${data.aws_region.this.name}:${data.aws_caller_identity.this.account_id}:parameter${secret}/*"
    ]
  }
}

data "aws_ssm_parameters_by_path" "secrets" {
  for_each = var.secrets

  path = each.value
}

data "aws_iam_policy_document" "task_execution" {
  statement {
    sid    = "Task"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cloudwatch" {
  name   = "${var.name}-role-cloudwatch-policy"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.cloudwatch.json
}

resource "aws_iam_role_policy" "cloudwatch_one_off" {
  for_each = var.one_off_commands

  name   = "${var.name}-${each.key}-cloudwatch-policy"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.cloudwatch_one_off[each.key].json
}

data "aws_iam_policy_document" "cloudwatch" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }
}

data "aws_iam_policy_document" "cloudwatch_one_off" {
  for_each = var.one_off_commands

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["${aws_cloudwatch_log_group.one_off[each.key].arn}:*"]
  }
}

resource "aws_alb_target_group" "this" {
  count = var.create_alb_target_group ? 1 : 0

  name                 = random_id.prefix.hex
  port                 = var.port.container
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = var.deregistration_delay # draining time
  target_type          = var.fargate ? "ip" : "instance"

  health_check {
    path                = var.health_check.path
    protocol            = "HTTP"
    timeout             = var.health_check_threshold.timeout
    interval            = var.health_check_threshold.interval
    healthy_threshold   = var.health_check_threshold.healthy
    unhealthy_threshold = var.health_check_threshold.unhealthy
    matcher             = var.health_check.matcher
  }

  tags = merge(local.tags, { "resource.group" = "network" })
}

# deployment group that can be attached to user deployer

resource "aws_iam_group" "deployment" {
  name = "${random_id.prefix.hex}-deployment"
}

resource "aws_iam_group_policy_attachment" "update_service" {
  group      = aws_iam_group.deployment.name
  policy_arn = aws_iam_policy.update_service.arn
}

resource "aws_iam_group_policy_attachment" "pass_role" {
  group      = aws_iam_group.deployment.name
  policy_arn = aws_iam_policy.pass_role.arn
}

resource "aws_iam_group_policy_attachment" "run_one_off_task" {
  for_each = var.one_off_commands

  group      = aws_iam_group.deployment.name
  policy_arn = aws_iam_policy.deployment_run_one_off_task[each.key].arn
}

# policy for updating service

resource "aws_iam_policy" "update_service" {
  name   = "${random_id.prefix.hex}-update-service"
  policy = data.aws_iam_policy_document.update_service.json

  tags = merge(local.tags, { "resource.group" = "identity" })
}

data "aws_iam_policy_document" "update_service" {
  statement {
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "ecs:DescribeServices",
      "ecs:UpdateService",
    ]

    resources = [aws_ecs_service.this.id]
  }
}

# policy for registering new task (IAM needs to pass role to task/execution role)

resource "aws_iam_policy" "pass_role" {
  name   = "${random_id.prefix.hex}-pass-role"
  policy = data.aws_iam_policy_document.pass_role.json

  tags = merge(local.tags, { "resource.group" = "identity" })
}

data "aws_iam_policy_document" "pass_role" {
  statement {
    actions = ["iam:PassRole", "iam:GetRole"]

    resources = [
      aws_iam_role.task_role.arn,
      aws_iam_role.task_execution.arn
    ]
  }
}

# policy for starting new one off task

resource "aws_iam_policy" "deployment_run_one_off_task" {
  for_each = var.one_off_commands

  name   = "${random_id.prefix.hex}-one-off-run-${each.key}"
  policy = data.aws_iam_policy_document.run_task[each.key].json
}

data "aws_iam_policy_document" "run_task" {
  for_each = var.one_off_commands

  statement {
    actions = ["ecs:RunTask"]

    resources = [
      "arn:aws:ecs:${data.aws_region.this.id}:${data.aws_caller_identity.this.id}:task-definition/${var.name}-${each.key}"
    ]
  }
}
