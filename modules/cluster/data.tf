data "aws_ami" "ecs_optimized" {
  owners = ["amazon"]

  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}
