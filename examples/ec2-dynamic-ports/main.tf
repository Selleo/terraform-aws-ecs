resource "random_id" "example" {
  byte_length = 4

  prefix = "ec2-"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"

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

  context = {
    namespace = "selleo"
    stage     = "dev"
    name      = "example"
  }

  name_prefix          = random_id.example.hex
  vpc_id               = module.vpc.vpc_id
  subnet_ids           = module.vpc.public_subnets
  instance_type        = "t3.nano"
  lb_security_group_id = module.lb.security_group_id

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
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.public_subnets
  force_https = false
}

module "service" {
  source = "../../modules/service"

  context = {
    namespace = "selleo"
    stage     = "dev"
    name      = "example"
  }

  name          = random_id.example.hex
  vpc_id        = module.vpc.vpc_id
  subnet_ids    = module.vpc.public_subnets
  cluster_id    = module.cluster.id
  desired_count = 1
  secrets       = ["/example-ecs-ec2/staging/api"]

  image = "qbart/go-http-server-noop:latest"
  envs = {
    ADDR = ":4000"
  }
  limits = {
    mem_min = 64
    mem_max = 128
    cpu     = 256
  }
  port = {
    host      = 0
    container = 4000
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

  path = "/example-ecs-ec2/staging/api"

  secrets = {
    APP_ENV = "staging"
  }
}

output "lb_dns" {
  value = "http://${module.lb.dns_name}"
}
