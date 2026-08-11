# Virtual (serverless) node pool

Demonstrates a virtual node pool (`oci_containerengine_virtual_node_pool`), the
OKE analog of EKS Fargate profiles. Virtual node pools require an **enhanced**
cluster with the **npn** (VCN-native) CNI and `Pod.Standard.*` shapes.

> **`terraform destroy` on this example can hang or fail.** Virtual node pool
> deletion on `enhanced` clusters has been observed getting stuck in
> `NEEDS_ATTENTION` with no error detail from OCI. If that happens, don't
> assume `terraform destroy` succeeded, verify with `oci ce virtual-node-pool
> list` and see [docs/testing.md](../../docs/testing.md#known-issue-enhanced-clusters-can-leave-resources-stuck-on-teardown)
> for the force-delete workaround.

## Usage

```bash
terraform init
terraform plan -var 'compartment_id=<your-compartment-ocid>'
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6 |
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
| <a name="output_virtual_node_pool_ids"></a> [virtual\_node\_pool\_ids](#output\_virtual\_node\_pool\_ids) | The OCIDs of the virtual node pools |
<!-- END_TF_DOCS -->
