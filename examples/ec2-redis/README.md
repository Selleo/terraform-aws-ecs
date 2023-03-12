# Example

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
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.1 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.4.3 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_cluster"></a> [cluster](#module\_cluster) | ../../modules/cluster | n/a |
| <a name="module_info"></a> [info](#module\_info) | Selleo/context/null | 0.3.0 |
| <a name="module_service"></a> [service](#module\_service) | ../../modules/service | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | Selleo/vpc/aws//modules/vpc | 0.6.0 |

## Resources

| Name | Type |
|------|------|
| [aws_security_group.lb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [null_resource.output_pem](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_id.example](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
<!-- END_TF_DOCS -->
