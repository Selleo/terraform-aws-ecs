resource "random_id" "example" {
  byte_length = 4

  prefix = "tf-example"
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

module "ecs-cluster" {
  source = "../../modules/cluster"

  name_prefix          = ""
  region               = "eu-central-1"
  vpc_id               = module.vpc.vpc_id
  subnet_ids           = module.vpc.private_subnets
  instance_type        = "t3.medium"
  lb_security_group_id = module.lb.security_group_id
}

module "lb" {
  source  = "Selleo/backend/aws//modules/load-balancer"
  version = "0.21.0"

  name       = "staging-internals"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets
}

module "ecs_service" {
  source = "../../modules/service"

  name           = "test"
  vpc_id         = module.vpc.vpc_id
  ecs_cluster_id = module.ecs_cluster.cluster_id
  desired_count  = 1

  container = {
    mem_reservation_units = 256
    port = 4567
    cpu_units      = 256
    mem_units      = 256
    command        = ["bundle", "exec", "ruby", "main.rb"],
    image          = "qbart/hello-ruby-sinatra:latest",
    container_port = 4567
    envs = {
      "APP_ENV" = "production"
    }
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = module.lb.id
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = module.ecs_service.lb_target_group_id
    type             = "forward"
  }
}