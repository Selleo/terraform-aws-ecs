resource "aws_iam_role" "instance_role" {
  name               = "${random_id.prefix.hex}-cluster-instance"
  assume_role_policy = data.aws_iam_policy_document.instance_role.json

  tags = var.tags
}

data "aws_iam_policy_document" "instance_role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "${random_id.prefix.hex}-cluster-instance"
  role = aws_iam_role.instance_role.name
}

resource "aws_iam_role_policy" "ecs_instance" {
  name   = "${random_id.prefix.hex}-ecs-instance"
  role   = aws_iam_role.instance_role.name
  policy = data.aws_iam_policy_document.ecs_instance.json
}

data "aws_iam_policy_document" "ecs_instance" {
  statement {
    effect = "Allow"
    actions = [
      "ecs:RegisterContainerInstance",
      "ecs:DeregisterContainerInstance",
      "ecs:DiscoverPollEndpoint",
      "ecs:Poll",
      "ecs:Submit*",
      "ecs:StartTelemetrySession",
    ]

    resources = ["*"]
  }
}
