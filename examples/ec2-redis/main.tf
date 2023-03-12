resource "random_id" "example" {
  byte_length = 4

  prefix = "redis-"
}

module "info" {
  source  = "Selleo/context/null"
  version = "0.3.0"

  namespace = "selleo"
  stage     = "dev"
  name      = "redis"
}

module "vpc" {
  source  = "Selleo/vpc/aws//modules/vpc"
  version = "0.6.0"

  context = module.info.context
}

resource "aws_security_group" "lb" {
  description = "No load balancer so we can define SG to create cluster"
  vpc_id      = module.vpc.id
  name        = "${random_id.example.hex}-lb"
}

module "cluster" {
  source = "../../modules/cluster"

  context = module.info.context

  name_prefix          = random_id.example.hex
  vpc_id               = module.vpc.id
  subnet_ids           = module.vpc.public_subnets
  instance_type        = "t3.nano"
  lb_security_group_id = aws_security_group.lb.id
  allow_ssh            = true

  autoscaling_group = {
    min_size         = 1
    max_size         = 5
    desired_capacity = 1
  }
}

module "service" {
  source = "../../modules/service"

  context = module.info.context

  name          = random_id.example.hex
  vpc_id        = module.vpc.id
  subnet_ids    = module.vpc.public_subnets
  cluster_id    = module.cluster.id
  desired_count = 1

  image = "redis:7.0.9"
  port = {
    host      = 6379
    container = 6379
  }
  limits = {
    mem_min = 64
    mem_max = 256
    cpu     = 256
  }
  create_alb_target_group = false
}

resource "null_resource" "output_pem" {
  provisioner "local-exec" {
    command = "echo '${module.cluster.private_key_pem}' > key.pem && chmod 0600 key.pem"
  }
}
