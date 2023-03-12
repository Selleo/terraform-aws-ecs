resource "random_id" "example" {
  byte_length = 4

  prefix = "static-"
}

module "info" {
  source  = "Selleo/context/null"
  version = "0.3.0"

  namespace = "selleo"
  stage     = "dev"
  name      = "static-ports"
}

module "vpc" {
  source  = "Selleo/vpc/aws//modules/vpc"
  version = "0.6.0"

  context = module.info.context
}

module "cluster" {
  source = "../../modules/cluster"

  context = module.info.context

  name_prefix          = random_id.example.hex
  vpc_id               = module.vpc.id
  subnet_ids           = module.vpc.public_subnets
  instance_type        = "t3.nano"
  lb_security_group_id = module.lb.security_group_id
  allow_ssh            = true

  autoscaling_group = {
    min_size         = 1
    max_size         = 5
    desired_capacity = 1
  }
}

module "lb" {
  source  = "Selleo/backend/aws//modules/load-balancer"
  version = "0.23.0"

  name        = random_id.example.hex
  vpc_id      = module.vpc.id
  subnet_ids  = module.vpc.public_subnets
  force_https = false
}

module "service" {
  source = "../../modules/service"

  context = module.info.context

  name          = random_id.example.hex
  vpc_id        = module.vpc.id
  subnet_ids    = module.vpc.public_subnets
  cluster_id    = module.cluster.id
  desired_count = 1

  image = "qbart/go-http-server-noop:latest"
  port = {
    host      = 8080
    container = 4000
  }
  limits = {
    mem_min = 128
    mem_max = 256
    cpu     = 256
  }
}

resource "aws_security_group_rule" "allow_8080" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = module.lb.security_group_id
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = module.lb.id
  port              = 8080
  protocol          = "HTTP"

  default_action {
    target_group_arn = module.service.lb_target_group_id
    type             = "forward"
  }


  provisioner "local-exec" {
    command = "echo '${module.cluster.private_key_pem}' > key.pem && chmod 0600 key.pem"
  }
}

output "lb_dns" {
  value = "http://${module.lb.dns_name}"
}
