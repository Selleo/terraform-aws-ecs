locals {
  ami = var.ami == "" ? data.aws_ami.ecs_optimized.id : var.ami

  tags = merge({
    "terraform.module"    = "Selleo/terraform-aws-ecs"
    "terraform.submodule" = "cluster"
    "context.namespace"   = var.context.namespace
    "context.stage"       = var.context.stage
    "context.name"        = var.context.name
  }, var.tags)
}

resource "random_id" "prefix" {
  byte_length = 4
  prefix      = "${var.name_prefix}-"
}

resource "aws_launch_template" "this" {
  name_prefix   = "${random_id.prefix.hex}-"
  image_id      = local.ami
  instance_type = var.instance_type
  key_name      = aws_key_pair.this.key_name

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type = var.root_block_configuration.volume_type
      volume_size = var.root_block_configuration.volume_size
    }
  }

  network_interfaces {
    associate_public_ip_address = var.associate_public_ip_address
    security_groups             = concat([aws_security_group.instance_sg.id], var.security_groups)
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.instance_profile.name
  }

  user_data = data.cloudinit_config.this.rendered
}

resource "aws_ecs_cluster" "this" {
  name = random_id.prefix.hex

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(local.tags, { "resource.group" = "compute" })
}

resource "aws_placement_group" "this" {
  name         = random_id.prefix.hex
  strategy     = var.placement_group.strategy # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/placement-groups.html
  spread_level = var.placement_group.spread_level

  tags = merge(local.tags, { "resource.group" = "compute" })
}

resource "aws_autoscaling_group" "this" {
  name                = random_id.prefix.hex
  vpc_zone_identifier = var.subnet_ids

  min_size              = var.autoscaling_group.min_size
  desired_capacity      = var.autoscaling_group.desired_capacity
  max_size              = var.autoscaling_group.max_size
  protect_from_scale_in = var.protect_from_scale_in

  placement_group      = aws_placement_group.this.id
  termination_policies = ["OldestInstance"]

  default_cooldown          = 300
  wait_for_capacity_timeout = "480s"
  health_check_grace_period = 15
  health_check_type         = "EC2"

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = random_id.prefix.hex
    propagate_at_launch = true
  }

  tag {
    key                 = var.ssm_tag_key
    value               = var.ssm_tag_value
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = merge(local.tags, { "resource.group" = "compute" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  force_delete = false

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [target_group_arns]
  }
}

resource "aws_security_group" "instance_sg" {
  description = "Controls direct access to application instances"
  vpc_id      = var.vpc_id
  name        = "${random_id.prefix.hex}-instance"

  tags = merge(local.tags, { "resource.group" = "network" })
}

resource "aws_security_group_rule" "ephemeral_port_range" {
  description              = "Allow dynamic port mapping for ECS"
  type                     = "ingress"
  from_port                = 32768
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = var.lb_security_group_id
  security_group_id        = aws_security_group.instance_sg.id
}

resource "aws_security_group_rule" "allow_all_outbound_ec2_instance" {
  description       = "Allow outgoing traffic"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.instance_sg.id
}

resource "aws_iam_role_policy" "efs" {
  count = var.efs == null ? 0 : 1

  name   = "${random_id.prefix.hex}-efs"
  role   = aws_iam_role.instance_role.name
  policy = data.aws_iam_policy_document.efs[count.index].json
}

data "aws_iam_policy_document" "efs" {
  count = var.efs == null ? 0 : 1

  statement {
    effect = "Allow"
    actions = [
      "elasticfilesystem:DescribeMountTargets",
      "elasticfilesystem:DescribeAccessPoints",
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeTags",
    ]

    resources = [
      var.efs.arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeAvailabilityZones",
    ]

    resources = ["*"]
  }
}


data "cloudinit_config" "this" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "ecs-init.sh"
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/scripts/user_data.sh.tpl",
      {
        ecs_cluster  = aws_ecs_cluster.this.name,
        ecs_loglevel = var.ecs_loglevel,
        ecs_tags = jsonencode(merge(var.tags, {
          "Name"      = random_id.prefix.hex,
          "ssm.group" = var.ssm_tag_value,
        }))
      }
    )
  }

  dynamic "part" {
    for_each = var.efs == null ? [] : ["efs"]

    content {
      filename     = "efs.sh"
      content      = <<SHELL
      #!/bin/sh
      pip3 install botocore
      SHELL
      content_type = "text/x-shellscript"
    }
  }

  dynamic "part" {
    for_each = var.cloudinit_scripts
    content {
      filename     = "${part.key}.sh"
      content      = part.value
      content_type = "text/x-shellscript"
    }
  }

  dynamic "part" {
    for_each = var.cloudinit_parts
    content {
      filename     = part.value["filename"]
      content      = part.value["content"]
      content_type = part.value["content_type"]
    }
  }
}

resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

resource "aws_key_pair" "this" {
  key_name   = "${random_id.prefix.hex}-ssh"
  public_key = tls_private_key.this.public_key_openssh

  tags = merge(local.tags, { "resource.group" = "keys" })
}

resource "aws_security_group_rule" "allow_ssh" {
  count = var.allow_ssh ? 1 : 0

  security_group_id = aws_security_group.instance_sg.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

resource "aws_iam_group" "deployment" {
  name = "${random_id.prefix.hex}-deployment"
}

resource "aws_iam_group_policy_attachment" "deployment" {
  group      = aws_iam_group.deployment.name
  policy_arn = aws_iam_policy.deployment.arn
}

resource "aws_iam_policy" "deployment" {
  name   = "${random_id.prefix.hex}-cluster-deployment"
  policy = data.aws_iam_policy_document.deployment.json
}

data "aws_iam_policy_document" "deployment" {
  statement {
    actions = ["ecs:DescribeTasks"]

    resources = [
      "*"
    ]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"

      values = [
        aws_ecs_cluster.this.arn,
      ]
    }
  }
}
