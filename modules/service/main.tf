data "aws_region" "current" {}

locals {
  task_definition = "${aws_ecs_task_definition.this.family}:${max(
    aws_ecs_task_definition.this.revision,
    data.aws_ecs_task_definition.this.revision,
  )}"

  container_definition_overrides = {
    command = var.command
  }
}

resource "random_id" "prefix" {
  byte_length = 4
  prefix      = "${var.name}-"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = var.name
  retention_in_days = var.log_retention_in_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "one_off" {
  for_each = var.one_off_commands

  name              = "${var.name}-${each.key}"
  retention_in_days = var.log_retention_in_days

  tags = var.tags
}

resource "aws_ecs_task_definition" "this" {
  family = var.name

  container_definitions = jsonencode(
    [
      merge({
        essential         = true,
        memoryReservation = var.container.mem_reservation_units,
        memory            = var.container.mem_units,
        cpu               = var.container.cpu_units,
        name              = var.name,
        image             = var.container.image,
        mountPoints       = [],
        volumesFrom       = [],
        portMappings = [
          {
            containerPort = var.container.port,
            hostPort      = 0,
            protocol      = "tcp",
          },
        ],

        environment = [
          for k, v in var.container.envs :
          {
            name  = k
            value = v
          }
        ],

        logConfiguration = {
          logDriver = "awslogs",
          options = {
            awslogs-group  = aws_cloudwatch_log_group.this.name,
            awslogs-region = data.aws_region.current.name,
          },
        },
      }, length(var.command) == 0 ? {} : local.container_definition_overrides) # merge only if command not empty
  ])

  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn = aws_iam_role.task_role.arn
  tags = var.tags
}

resource "aws_ecs_task_definition" "one_off" {
  for_each = var.one_off_commands

  family = "${var.name}-${each.key}"

  container_definitions = jsonencode(
    [
      {
        command           = [each.key]
        essential         = true,
        memoryReservation = var.container.mem_reservation_units,
        memory            = var.container.mem_units,
        cpu               = var.container.cpu_units,
        name              = var.name,
        image             = var.container.image,
        mountPoints       = [],
        volumesFrom       = [],
        portMappings      = [],

        environment = [
          for k, v in var.container.envs :
          {
            name  = k
            value = v
          }
        ],

        logConfiguration = {
          logDriver = "awslogs",
          options = {
            awslogs-group  = aws_cloudwatch_log_group.one_off[each.key].name,
            awslogs-region = data.aws_region.current.name,
          },
        },
      }
  ])

  tags = var.tags
}

data "aws_ecs_task_definition" "this" {
  task_definition = aws_ecs_task_definition.this.family
  depends_on      = [aws_ecs_task_definition.this]
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.ecs_cluster_id
  task_definition = local.task_definition

  load_balancer {
    target_group_arn = aws_alb_target_group.this.arn
    container_name   = var.name
    container_port   = var.container.port
  }

  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.avaiability-zones"
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "instanceId"
  }

  tags = var.tags
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

  tags = var.tags
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

  tags = var.tags
}

resource "aws_iam_role_policy" "task" {
  name   = "${random_id.prefix.hex}-ecs-task"
  role   = aws_iam_role.task_execution.name
  policy = data.aws_iam_policy_document.task.json
}

data "aws_iam_policy_document" "task" {
  statement {
    sid    = "Task"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
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
  name                 = var.name
  port                 = var.container.port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = 30 # draining time

  health_check {
    path                = var.health_check.path
    protocol            = "HTTP"
    timeout             = 10
    interval            = 15
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = var.health_check.matcher
  }

  tags = var.tags
}
