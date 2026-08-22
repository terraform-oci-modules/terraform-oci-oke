# OKE control-plane logging

Minimal example: a basic OKE cluster (no node pools) with control-plane
logging enabled through OCI Logging, mirroring EKS's `enabled_log_types` /
`create_cloudwatch_log_group`.

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

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | The OCID of the OKE cluster |
| <a name="output_control_plane_log_group_id"></a> [control\_plane\_log\_group\_id](#output\_control\_plane\_log\_group\_id) | The OCID of the control-plane log group |
| <a name="output_control_plane_log_ids"></a> [control\_plane\_log\_ids](#output\_control\_plane\_log\_ids) | Control-plane log OCIDs by category |
<!-- END_TF_DOCS -->
