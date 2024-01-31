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

  # when no ports are specified, we assume this is a worker
  is_worker = var.port == null ? true : false
  # when LB is used ports must be specified
  needs_lb = var.create_alb_target_group && !local.is_worker

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
  family                   = random_id.prefix.hex
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      essential         = true,
      memoryReservation = 32
      memory            = 64
      cpu               = 64
      name              = var.name
      image             = "qbart/go-http-server-noop:0.3.0"
      # workers do not need port mappings
      portMappings = local.is_worker ? [] : [
        {
          containerPort = var.port,
          hostPort      = 0,
          protocol      = "tcp",
        },
      ],
      environment = [
        {
          name  = "APP_ENV"
          value = var.context.stage
        },
        {
          name  = "ADDR"
          value = var.port == null ? ":3000" : ":${var.port}"
        },
      ],

      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name,
          awslogs-region        = data.aws_region.this.name,
          awslogs-stream-prefix = "ecs",
        },
      },
    }
  ])

  tags = merge(local.tags, { "resource.group" = "compute" })
}

resource "aws_ecs_task_definition" "one_off" {
  for_each = var.one_off_commands

  family                   = "${random_id.prefix.hex}-${each.key}"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      essential         = true,
      memoryReservation = 32
      memory            = 64
      cpu               = 64
      name              = var.name
      image             = "busybox:latest"
      command           = ["sh", "-c", "echo 'Hi'"]

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

  tags = merge(local.tags, { "resource.group" = "compute" })
}

resource "aws_ecs_service" "this" {
  name                   = var.name
  cluster                = var.cluster_id
  task_definition        = "${aws_ecs_task_definition.this.family}:${aws_ecs_task_definition.this.revision}"
  enable_execute_command = var.enable_execute_command

  launch_type = "EC2"

  dynamic "load_balancer" {
    for_each = local.needs_lb ? [1] : []

    content {
      target_group_arn = aws_alb_target_group.this[0].arn
      container_name   = var.name
      container_port   = var.port
    }
  }

  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  dynamic "ordered_placement_strategy" {
    for_each = local.ordered_placement_strategy

    content {
      type  = ordered_placement_strategy.value.type
      field = ordered_placement_strategy.value.field
    }
  }

  tags = merge(local.tags, { "resource.group" = "compute" })

  lifecycle {
    ignore_changes = [
      task_definition,
    ]
  }
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

resource "aws_iam_role_policy" "task_role" {
  name   = "${random_id.prefix.hex}-task"
  role   = aws_iam_role.task_role.name
  policy = data.aws_iam_policy_document.task_role.json
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

data "aws_iam_policy_document" "task_role" {
  statement {
    sid    = "Task"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]

    resources = ["*"]
  }
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
  name   = "${random_id.prefix.hex}-role-cloudwatch-policy"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.cloudwatch.json
}

resource "aws_iam_role_policy" "cloudwatch_one_off" {
  for_each = var.one_off_commands

  name   = "${random_id.prefix.hex}-${each.key}-cloudwatch-policy"
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
  count = local.needs_lb ? 1 : 0

  name                 = random_id.prefix.hex
  port                 = var.port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = var.deregistration_delay # draining time
  target_type          = "instance"

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
      "arn:aws:ecs:${data.aws_region.this.id}:${data.aws_caller_identity.this.id}:task-definition/${random_id.prefix.hex}-${each.key}"
    ]
  }
}
