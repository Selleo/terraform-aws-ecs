resource "random_id" "example" {
  byte_length = 4

  prefix = "ec2-worker-"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = random_id.example.hex
  cidr = "10.0.0.0/16"

  azs             = ["eu-central-1a", "eu-central-1b"]
  private_subnets = ["10.0.1.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
}

# simulate load balancer SG - we don't need real LB here
resource "aws_security_group" "dummy_lb" {
  vpc_id = module.vpc.vpc_id
  name   = "${random_id.example.hex}-dummy-lb"
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
  lb_security_group_id = aws_security_group.dummy_lb.id
  allow_ssh            = true
  ssh_cidr_ipv4        = ["0.0.0.0/0"]

  autoscaling_group = {
    min_size         = 1
    max_size         = 5
    desired_capacity = 1
  }
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

  labels = {
    "this.is.label" = "true"
  }

  image = "qbart/go-http-server-noop:latest"
  envs = {
    ADDR = ":4000"
  }
  limits = {
    mem_min = 128
    mem_max = 256
    cpu     = 256
  }
}

resource "null_resource" "output_pem" {
  provisioner "local-exec" {
    command = "echo '${module.cluster.private_key_pem}' > key.pem && chmod 0600 key.pem"
  }
}
