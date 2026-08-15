# Cluster add-ons

Demonstrates OKE-managed add-ons (`oci_containerengine_addon`). Add-ons require
an **enhanced** cluster. This example turns on several optional add-ons
(`KubernetesMetricsServer`, `CertManager`, `ClusterAutoscaler`) alongside the
essential `CoreDNS`, and shows version pinning + `configurations`.

Turn an optional add-on **on** by adding its key to `addons`; turn it
**off** by removing the key. The catalog is Kubernetes-version specific:

```bash
oci ce addon-option list --kubernetes-version v1.36.1 --all --query 'data[*].name'
```

> `ClusterAutoscaler` and `ObservabilityAgent` call OCI APIs and require IAM
> (dynamic group + policy) granted outside this module.

> **Applying or destroying this example can fail with OCI platform errors
> specific to `enhanced` clusters.** Addon creation (`KubernetesMetricsServer`
> in particular) has been observed racing with OKE's own addon provisioning
> on brand-new clusters (`expected ACTIVE, got DELETING`), and node pool
> deletion can hang in `NEEDS_ATTENTION` with no error detail. Both are
> OCI-side issues, not something this module's config controls. See
> [docs/testing.md](../../docs/testing.md#known-issue-enhanced-clusters-can-leave-resources-stuck-on-teardown)
> for what to expect and the force-delete workaround if teardown gets stuck.

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
| <a name="output_cluster_addons"></a> [cluster\_addons](#output\_cluster\_addons) | The OKE-managed addons that were enabled |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | The OCID of the OKE cluster |
| <a name="output_node_pool_ids"></a> [node\_pool\_ids](#output\_node\_pool\_ids) | The OCIDs of the managed node pools |
<!-- END_TF_DOCS -->
