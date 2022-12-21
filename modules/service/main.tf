data "aws_region" "this" {}
data "aws_caller_identity" "this" {}

locals {
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
  family                   = var.name
  network_mode             = var.fargate ? "awsvpc" : "bridge"
  requires_compatibilities = var.fargate ? ["FARGATE"] : ["EC2"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task_role.arn

  cpu    = var.container.cpu_units
  memory = var.container.mem_units

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
            hostPort      = var.fargate ? var.container.port : 0,
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

  tags = var.tags
}

resource "aws_ecs_task_definition" "one_off" {
  for_each = var.one_off_commands

  family                   = "${var.name}-${each.key}"
  network_mode             = var.fargate ? "awsvpc" : "bridge"
  requires_compatibilities = var.fargate ? ["FARGATE"] : ["EC2"]
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task_role.arn

  cpu    = var.fargate ? var.container.cpu_units : null
  memory = var.fargate ? var.container.mem_units : null

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

  tags = var.tags
}

data "aws_ecs_task_definition" "this" {
  task_definition = aws_ecs_task_definition.this.family
  depends_on      = [aws_ecs_task_definition.this]
}

resource "aws_security_group" "this" {
  name   = "${random_id.prefix.hex}-ecs-tasks"
  vpc_id = var.vpc_id
}

# needed by fargate
resource "aws_security_group_rule" "egress" {
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
  security_group_id = aws_security_group.this.id
  type              = "ingress"
  from_port         = var.container.port
  to_port           = var.container.port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_id
  task_definition = local.task_definition

  launch_type = var.fargate ? "FARGATE" : "EC2"

  load_balancer {
    target_group_arn = aws_alb_target_group.this.arn
    container_name   = var.name
    container_port   = var.container.port
  }

  dynamic "network_configuration" {
    for_each = var.fargate ? [1] : []

    content {
      security_groups  = [aws_security_group.this.id]
      subnets          = var.subnet_ids
      assign_public_ip = var.public_ip
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

resource "aws_iam_role_policy" "task_execution" {
  name   = "${random_id.prefix.hex}-task-execution"
  role   = aws_iam_role.task_execution.name
  policy = data.aws_iam_policy_document.task_execution.json
}

resource "aws_iam_role_policy" "ssm_get" {
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
  name                 = var.name
  port                 = var.container.port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = 30 # draining time
  target_type          = var.fargate ? "ip" : "instance"

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
