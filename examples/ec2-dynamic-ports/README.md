# Example

TODO

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 4.48.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.4.3 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_cluster"></a> [cluster](#module\_cluster) | ../../modules/cluster | n/a |
| <a name="module_lb"></a> [lb](#module\_lb) | Selleo/backend/aws//modules/load-balancer | 0.23.0 |
| <a name="module_secrets"></a> [secrets](#module\_secrets) | Selleo/ssm/aws//modules/parameters | 0.2.0 |
| <a name="module_service"></a> [service](#module\_service) | ../../modules/service | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | ~> 4.0 |

## Resources

| Name | Type |
|------|------|
| [aws_alb_listener.http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/alb_listener) | resource |
| [random_id.example](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_lb_dns"></a> [lb\_dns](#output\_lb\_dns) | n/a |
<!-- END_TF_DOCS -->
