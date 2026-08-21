# Complete OKE cluster

Full-featured example: an **enhanced** OKE cluster with **VCN-native (npn)** pod
networking, OIDC discovery (workload identity), an OKE-managed addon (CoreDNS),
a managed node pool, and a virtual (serverless) node pool.

> **Applying or destroying this example can fail with OCI platform errors
> specific to `enhanced` clusters.** Addon creation (`KubernetesMetricsServer`
> in particular) has been observed racing with OKE's own addon provisioning
> on brand-new clusters (`expected ACTIVE, got DELETING`), and node pool /
> virtual node pool deletion can hang in `NEEDS_ATTENTION` with no error
> detail. Both are OCI-side issues, not something this module's config
> controls. See [docs/testing.md](../../docs/testing.md#known-issue-enhanced-clusters-can-leave-resources-stuck-on-teardown)
> for what to expect and the force-delete workaround if teardown gets stuck.

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
| <a name="input_ssh_authorized_keys"></a> [ssh\_authorized\_keys](#input\_ssh\_authorized\_keys) | SSH public key string to authorize on worker nodes | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_addons"></a> [cluster\_addons](#output\_cluster\_addons) | The OKE-managed addons |
| <a name="output_cluster_endpoints"></a> [cluster\_endpoints](#output\_cluster\_endpoints) | The endpoints of the OKE cluster |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | The OCID of the OKE cluster |
| <a name="output_cluster_oidc_discovery_endpoint"></a> [cluster\_oidc\_discovery\_endpoint](#output\_cluster\_oidc\_discovery\_endpoint) | The OIDC discovery endpoint of the cluster |
| <a name="output_node_pool_ids"></a> [node\_pool\_ids](#output\_node\_pool\_ids) | The OCIDs of the managed node pools |
| <a name="output_np_managed_secondary_vnics"></a> [np\_managed\_secondary\_vnics](#output\_np\_managed\_secondary\_vnics) | Secondary VNIC attachments on the np-managed pool's node\_pool resource |
| <a name="output_virtual_node_pool_ids"></a> [virtual\_node\_pool\_ids](#output\_virtual\_node\_pool\_ids) | The OCIDs of the virtual node pools |
<!-- END_TF_DOCS -->
