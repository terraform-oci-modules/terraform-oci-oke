# Complete OKE cluster

Full-featured example: an **enhanced** OKE cluster with **VCN-native (npn)** pod
networking, OIDC discovery (workload identity), an OKE-managed addon (CoreDNS),
a managed node pool, and a virtual (serverless) node pool.

> If a node pool delete gets stuck in `NEEDS_ATTENTION`, see
> [docs/testing.md](../../docs/testing.md#node-pool-teardown) for the
> force-delete workaround.

## Usage

```bash
terraform init
terraform plan -var 'compartment_id=<your-compartment-ocid>'
terraform apply -var 'compartment_id=<your-compartment-ocid>'
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7 |
| <a name="requirement_oci"></a> [oci](#requirement\_oci) | >= 8.21.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_oke"></a> [oke](#module\_oke) | ../../ | n/a |
| <a name="module_vcn"></a> [vcn](#module\_vcn) | terraform-oci-modules/vcn/oci | ~> 0.7 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_compartment_id"></a> [compartment\_id](#input\_compartment\_id) | The OCID of the compartment where resources will be created | `string` | n/a | yes |
| <a name="input_ssh_authorized_keys"></a> [ssh\_authorized\_keys](#input\_ssh\_authorized\_keys) | SSH public key string to authorize on worker nodes | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_addons"></a> [cluster\_addons](#output\_cluster\_addons) | The OKE-managed addons |
| <a name="output_cluster_endpoints"></a> [cluster\_endpoints](#output\_cluster\_endpoints) | The endpoints of the OKE cluster |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | The OCID of the OKE cluster |
| <a name="output_cluster_oidc_discovery_endpoint"></a> [cluster\_oidc\_discovery\_endpoint](#output\_cluster\_oidc\_discovery\_endpoint) | The OIDC discovery endpoint of the cluster |
| <a name="output_node_pool_ids"></a> [node\_pool\_ids](#output\_node\_pool\_ids) | The OCIDs of the managed node pools |
| <a name="output_virtual_node_pool_ids"></a> [virtual\_node\_pool\_ids](#output\_virtual\_node\_pool\_ids) | The OCIDs of the virtual node pools |
<!-- END_TF_DOCS -->
