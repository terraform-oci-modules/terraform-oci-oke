# Managed node pools

Demonstrates managed node pools (`oci_containerengine_node_pool`): a fixed-size
pool spread across two availability domains and an autoscaler-managed pool whose
size is ignored by Terraform after creation.

## Usage

```bash
terraform init
terraform plan -var 'compartment_id=<your-compartment-ocid>'
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7 |
| <a name="requirement_oci"></a> [oci](#requirement\_oci) | >= 6.0 |

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
| <a name="output_autoscaled_pool_secondary_vnics"></a> [autoscaled\_pool\_secondary\_vnics](#output\_autoscaled\_pool\_secondary\_vnics) | Secondary VNIC attachments on the autoscaled pool's node\_pool resource |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | The OCID of the OKE cluster |
| <a name="output_cluster_ip_families"></a> [cluster\_ip\_families](#output\_cluster\_ip\_families) | Resolved IP families for the cluster |
| <a name="output_cluster_service_cidr"></a> [cluster\_service\_cidr](#output\_cluster\_service\_cidr) | Resolved Kubernetes service CIDR block |
| <a name="output_node_pool_ids"></a> [node\_pool\_ids](#output\_node\_pool\_ids) | The OCIDs of the managed node pools |
<!-- END_TF_DOCS -->
