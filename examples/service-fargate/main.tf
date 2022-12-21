resource "random_id" "example" {
  byte_length = 4

  prefix = "fargate"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = random_id.example.hex
  cidr = "10.0.0.0/16"

  azs             = ["eu-central-1a", "eu-central-1b"]
  private_subnets = ["10.0.1.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  single_nat_gateway = true
  enable_nat_gateway = false
  enable_vpn_gateway = false
}

module "cluster" {
  source = "../../modules/cluster"

  name_prefix          = random_id.example.hex
  vpc_id               = module.vpc.vpc_id
  subnet_ids           = module.vpc.public_subnets
  instance_type        = "t3.nano"
  lb_security_group_id = module.lb.security_group_id
}

module "lb" {
  source  = "Selleo/backend/aws//modules/load-balancer"
  version = "0.23.0"

  name        = random_id.example.hex
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.public_subnets
  force_https = false
}

module "service" {
  source = "../../modules/service"

  name          = random_id.example.hex
  vpc_id        = module.vpc.vpc_id
  subnet_ids    = module.vpc.public_subnets
  cluster_id    = module.cluster.id
  desired_count = 1
  secrets       = ["/example/staging/api"]
  fargate       = true

  container = {
    mem_reservation_units = 128
    cpu_units             = 256
    mem_units             = 512

    image = "qbart/go-http-server-noop:latest",
    port  = 4000
  }

  depends_on = [module.secrets]
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = module.lb.id
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = module.service.lb_target_group_id
    type             = "forward"
  }
}

module "secrets" {
  source  = "Selleo/ssm/aws//modules/parameters"
  version = "0.2.0"

  context = {
    namespace = "example"
    stage     = "staging"
    name      = "api"
  }

  path = "/example/staging/api"

  secrets = {
    APP_ENV = "staging"
  }
}
