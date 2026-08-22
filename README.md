# Terraform OCI OKE module

Terraform module to provision an [Oracle Container Engine for Kubernetes (OKE)](https://docs.oracle.com/en-us/iaas/Content/ContEng/home.htm)
cluster with managed, virtual (serverless), and self-managed node pools.

This is the OCI counterpart of the
[`terraform-aws-eks`](https://github.com/terraform-aws-modules/terraform-aws-eks)
module. It mirrors the EKS scope (cluster + node groups + addons) and maps each
concept to its idiomatic OKE equivalent. Networking is supplied as input, build
it with the sibling [`terraform-oci-vcn`](../terraform-oci-vcn) module. See
[docs/feature_parity.md](docs/feature_parity.md) for the full EKS to OKE mapping
and the gap analysis (what does not port, what is out of scope, and what is
still on the backlog).

## Usage

```hcl
module "oke" {
  source  = "terraform-oci-modules/oke/oci"
  version = "~> 0.1"

  name               = "my-cluster"
  compartment_id     = var.compartment_id
  kubernetes_version = "v1.36.1"
  cluster_type       = "basic"
  cni_type           = "flannel"

  vcn_id                  = module.vcn.vcn_id
  control_plane_subnet_id = module.vcn.private_subnets[0]
  worker_subnet_id        = module.vcn.private_subnets[0]
  service_lb_subnet_id    = module.vcn.public_subnets[0]
  # Private control plane by default; see docs/network_connectivity.md for access options.

  node_pools = {
    np1 = {
      shape                = "VM.Standard.E4.Flex"
      ocpus                = 2
      memory               = 16
      size                 = 2
      availability_domains = [1]
    }
  }
}
```

## Node pool types

| Type | Variable | Resource | EKS analog |
|------|----------|----------|------------|
| Managed | `node_pools` | `oci_containerengine_node_pool` | `eks_managed_node_groups` |
| Virtual (serverless) | `virtual_node_pools` | `oci_containerengine_virtual_node_pool` | `fargate_profiles` |
| Self-managed | `self_managed_node_pools` | `oci_core_instance_pool` | `self_managed_node_groups` |

Virtual node pools require `cluster_type = "enhanced"` and `cni_type = "npn"`.
OKE-managed addons (`addons`) require `cluster_type = "enhanced"`.

> **Bumping `kubernetes_version` does not roll already-running nodes by default** -
> only the pool's template/image updates immediately. Managed pools need
> `node_cycling.enabled = true` (which itself requires `cluster_type = "enhanced"`) to
> actually replace nodes; self-managed pools have no automated rolling-upgrade path at
> all. See [docs/upgrades.md](docs/upgrades.md) for the full, live-verified behavior.

> **`enhanced` clusters have known OCI-side reliability issues on this
> module's tested tenancy**, independent of anything this module configures:
> `addons` creation can race with OKE's own addon provisioning on a
> brand-new cluster, and node pool / virtual node pool deletion can hang in
> `NEEDS_ATTENTION` with no error detail from OCI. Both were reproduced
> repeatedly against a real tenancy; neither reproduces on `basic` clusters.
> See [docs/testing.md](docs/testing.md#known-issue-enhanced-clusters-can-leave-resources-stuck-on-teardown)
> for what to expect and the force-delete workaround.

## Cluster add-ons

OKE exposes a fixed catalog of **managed** add-ons (`oci_containerengine_addon`):
OKE installs, upgrades, and reconciles them for you. They are the OCI analog of
EKS managed add-ons (`vpc-cni`, `coredns`, …). Two important constraints:

- **Enhanced clusters only.** With `cluster_type = "basic"` no add-on can be
  enabled (the module fails at plan if you try).
- **Thin config surface.** Each add-on accepts only the flat `{ key, value }`
  pairs OKE defines for it, not a free-form Helm `values.yaml`. Richer settings
  go in as JSON encoded into a string value. For anything outside the catalog
  (Cilium, Prometheus, ArgoCD, Karpenter, Multus, …), self-manage it with the
  `helm`/`kubernetes` providers downstream using this module's `cluster_id` and
  `kubeconfig` outputs.

### Essential vs optional

**Essential** add-ons are installed and managed automatically on every enhanced
cluster. You may *configure or version* them via `addons`, but they
cannot be turned off: `CoreDNS`, `KubeProxy`, and the CNI (`Flannel` for
`cni_type = "flannel"` or `OciVcnIpNative` for `cni_type = "npn"`).

**Optional** add-ons are off by default and turned on by adding them to
`addons`; remove the key to turn them off again:

| Add-on | Purpose |
|--------|---------|
| `ClusterAutoscaler` | Node autoscaling (needs IAM, see below) |
| `KubernetesMetricsServer` | metrics-server (HPA, `kubectl top`) |
| `CertManager` | cert-manager |
| `NativeIngressController` | OCI load-balancer-backed ingress |
| `Istio` | Service mesh |
| `KubernetesDashboard` | Web dashboard |
| `NodeFeatureDiscovery` | Node feature labels |
| `CsiDriverSmb` | SMB/CIFS persistent volumes |
| `NvidiaGpuPlugin` / `NvidiaGpuOperator` / `NvidiaNetworkOperator` / `AmdGpuPlugin` / `AmdGpuOperator` | GPU / RDMA enablement |
| `ObservabilityAgent` | Metrics/logs to OCI Monitoring (needs IAM) |
| `NodeProblemDetector` | Node health reporting |
| `OracleDatabaseOperator` / `WeblogicKubernetesOperator` | Oracle workload operators |

> The catalog is **Kubernetes-version specific**. List exactly what is available
> for your version with:
>
> ```bash
> oci ce addon-option list --kubernetes-version v1.36.1 --all --query 'data[*].name'
> ```

### Turning add-ons on/off

```hcl
cluster_type = "enhanced"   # required for any add-on

addons = {
  # Optional add-on, latest version, default config.
  KubernetesMetricsServer = {}

  # Optional add-on with a pinned version and configuration values.
  ClusterAutoscaler = {
    version = "v1.34.3"
    configurations = [
      { key = "numOfReplicas", value = "2" },
      { key = "authType", value = "workload" },
    ]
  }

  # Essential add-on: cannot be disabled via addons, but can be reconfigured.
  CoreDNS = {}
}
# Removing a key disables that optional add-on on the next apply.

# To turn OFF an add-on OKE installs by default (e.g. to replace it), list it in
# addons_to_remove. This runs `oci ce cluster disable-addon` at apply
# time and so requires the OCI CLI on the apply host.
addons_to_remove = {
  KubernetesDashboard = { remove_k8s_resources = true }
}
```

> **IAM:** add-ons that call OCI APIs, notably `ClusterAutoscaler` and
> `ObservabilityAgent`, require dynamic-group/policy grants. This module does
> **not** create IAM (see below and [docs/feature_parity.md](docs/feature_parity.md));
> grant those alongside it.

## Required IAM (granted outside this module)

By design this module creates **no IAM**, it stays compartment-scoped and needs
no tenancy-level permissions or home-region provider (matching
`terraform-oci-compute-instance`). Some features only work once the right
dynamic groups + policies exist. Create them separately (Terraform with a
home-region provider, the Console, or the OCI CLI). Dynamic groups live in the
tenancy (root) and policies are created in the **home region**.

Grant only what the features you enable require:

| If you use… | Create this grant |
|-------------|-------------------|
| `cluster_kms_key_id` (secrets encryption) | DG matching `resource.type='cluster'`; `Allow dynamic-group <cluster-dg> to use keys in compartment id <c> where target.key.id='<key>'` and `… to read instance-images in compartment id <c>`. **Required or cluster creation fails** |
| `ClusterAutoscaler` add-on | DG of autoscaler nodes; `Allow dynamic-group <as-dg> to manage cluster-node-pools / compute-management-family / instance-family / volume-family in compartment id <c>`, `to use subnets / vnics`, `to read virtual-network-family`, `to inspect compartments` |
| `self_managed_node_pools` (node join) | DG of worker instances; `Allow dynamic-group <wk-dg> to {CLUSTER_JOIN} in compartment id <c>` (+ KMS `use key-delegates` statements if `volume_kms_key_id` is set) |
| Workload identity / Karpenter | Workload-identity policy: `Allow any-user to manage … where all { request.principal.type='workload', request.principal.cluster_id='<id>', request.principal.namespace='<ns>', request.principal.service_account='<sa>' }` |
| Cluster-managed NSGs / IPv6 | `Allow any-user to manage network-security-groups in compartment id <c> where request.principal.type='cluster'` |
| `Service` of `type: LoadBalancer` with a **reserved/floating public IP** | No dynamic group needed. `request.principal.type='cluster'` is a built-in principal, not one you create. `Allow any-user to read public-ips in tenancy where request.principal.type='cluster'` and `… to manage floating-ips in tenancy where request.principal.type='cluster'`. A **default** classic LB with an OCI-assigned ephemeral IP needs neither grant (verified end to end, see [docs/service_load_balancers.md](docs/service_load_balancers.md)). |
| `Service` with `oci.oraclecloud.com/load-balancer-type: "nlb"` (Network Load Balancer) | `Allow any-user to use private-ips in tenancy where all { request.principal.type='cluster', request.principal.compartment.id='<c>' }` and `… to manage public-ips in tenancy where all { request.principal.type='cluster', request.principal.compartment.id='<c>' }` |

(Statement templates lifted from the old `terraform-oci-oke` IAM submodule. Creating
them from this module would require a second, home-region provider and
tenancy-level permissions, which is why it is out of scope, see
[docs/feature_parity.md](docs/feature_parity.md#gap-class-b-deliberate-scope-exclusions).)

## Examples

- [simple](examples/simple) - basic cluster + one managed node pool
- [complete](examples/complete) - enhanced cluster, npn CNI, addons, OIDC, managed + virtual pools
- [cluster-addons](examples/cluster-addons) - toggling OKE-managed add-ons on/off
- [managed-node-pool](examples/managed-node-pool) - fixed + autoscaler-managed pools
- [virtual-node-pool](examples/virtual-node-pool) - serverless pods
- [self-managed-node-pool](examples/self-managed-node-pool) - instance-pool nodes

## OCI notes

- **Kubernetes version** uses a `v` prefix (e.g. `v1.36.1`); list supported
  versions with `oci ce node-pool-options get --node-pool-option-id all`.
- **Availability domains** are referenced by number (`[1, 2, 3]`) and resolved to
  tenancy-specific AD names by the module.
- **Worker images** are resolved automatically from the pool's Kubernetes version
  and shape architecture; override per pool with `image_id`.
- **KMS keys and IAM** are inputs, not created here, see
  [docs/feature_parity.md](docs/feature_parity.md).
- **Control plane access** defaults to a **private** endpoint
  (`control_plane_is_public = false`), like the EKS module. The `examples/` flip it
  public so they are reachable for demos; keep it private in production and reach it
  via a bastion / operator host, the OCI Bastion service, or VPN. This module does
  not provision any access infrastructure, see
  [docs/network_connectivity.md](docs/network_connectivity.md).
- **`Service` of `type: LoadBalancer`** creates a real OCI Load Balancer or Network
  Load Balancer automatically via OKE's `oci-cloud-controller-manager` (no module
  code involved beyond `service_lb_subnet_id` and `service_lb_backend_nsg_ids`). Verified working
  end to end on `examples/simple` with no extra IAM. Reserved public IPs, Network Load
  Balancers, and NSG-managed LB rules do need grants this module does **not** create
  (see the Required IAM table above). Note the CCM also **edits the security lists** on
  the load balancer and worker subnets by default, without producing Terraform drift.
  See [docs/service_load_balancers.md](docs/service_load_balancers.md) for annotations,
  the verified test, and the exact grants needed.

## Network security groups

Networking is normally supplied by the sibling
[`terraform-oci-vcn`](../terraform-oci-vcn) module (pass NSG OCIDs via
`control_plane_nsg_ids` / `worker_nsg_ids` / `pod_nsg_ids`). For convenience the
module can also create its own NSGs:

- `create_control_plane_nsg` / `create_worker_nsg` create a control-plane and a worker NSG.
- When created, each NSG is seeded with a **recommended OKE ruleset** (the OKE analog
  of EKS `node_security_group_enable_recommended_rules`). It covers control-plane ↔
  worker ↔ pod communication (kube-apiserver `6443`, kubelet `10250`, OKE `12250`),
  ICMP type 3 code 4 path-MTU discovery, egress to the Oracle Services Network, and
  (by default) worker egress to the internet. Disable via
  `control_plane_nsg_enable_recommended_rules` / `worker_nsg_enable_recommended_rules`,
  drop internet egress with `worker_allow_internet_egress = false`, and restrict the
  API server to specific CIDRs with `control_plane_allowed_cidrs`.
- Pod-tier rules are added only for `cni_type = "npn"` when a `pod_nsg_ids` value is
  supplied. Add any extra rules through `*_nsg_ingress_rules` / `*_nsg_egress_rules`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7 |
| <a name="requirement_oci"></a> [oci](#requirement\_oci) | >= 6.0, < 8.16.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_oci"></a> [oci](#provider\_oci) | >= 6.0, < 8.16.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_node_pool"></a> [node\_pool](#module\_node\_pool) | ./modules/node-pool | n/a |
| <a name="module_self_managed_node_pool"></a> [self\_managed\_node\_pool](#module\_self\_managed\_node\_pool) | ./modules/self-managed-node-pool | n/a |
| <a name="module_virtual_node_pool"></a> [virtual\_node\_pool](#module\_virtual\_node\_pool) | ./modules/virtual-node-pool | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [oci_containerengine_addon.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/containerengine_addon) | resource |
| [oci_containerengine_cluster.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/containerengine_cluster) | resource |
| [oci_core_network_security_group.control_plane](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_network_security_group) | resource |
| [oci_core_network_security_group.worker](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_network_security_group) | resource |
| [oci_core_network_security_group_security_rule.control_plane_egress](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_network_security_group_security_rule) | resource |
| [oci_core_network_security_group_security_rule.control_plane_ingress](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_network_security_group_security_rule) | resource |
| [oci_core_network_security_group_security_rule.control_plane_recommended](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_network_security_group_security_rule) | resource |
| [oci_core_network_security_group_security_rule.worker_egress](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_network_security_group_security_rule) | resource |
| [oci_core_network_security_group_security_rule.worker_ingress](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_network_security_group_security_rule) | resource |
| [oci_core_network_security_group_security_rule.worker_recommended](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_network_security_group_security_rule) | resource |
| [oci_logging_log.control_plane](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/logging_log) | resource |
| [oci_logging_log_group.control_plane](https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/logging_log_group) | resource |
| [terraform_data.remove_addon](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [oci_containerengine_addon_options.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/containerengine_addon_options) | data source |
| [oci_containerengine_cluster_kube_config.private](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/containerengine_cluster_kube_config) | data source |
| [oci_containerengine_cluster_kube_config.public](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/containerengine_cluster_kube_config) | data source |
| [oci_containerengine_node_pool_option.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/containerengine_node_pool_option) | data source |
| [oci_core_services.recommended](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/core_services) | data source |
| [oci_identity_availability_domains.this](https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/identity_availability_domains) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_addons"></a> [addons](#input\_addons) | OKE-managed addons to enable, keyed by addon name (e.g. "CertManager",<br/>"ClusterAutoscaler", "KubernetesMetricsServer"). Requires<br/>cluster\_type = "enhanced". Maps to the EKS addons variable.<br/><br/>Per addon:<br/>  - version:                          pin a version, or null for latest.<br/>  - override\_existing:                take over an addon already installed<br/>                                      out-of-band (e.g. via kubectl/Helm).<br/>  - remove\_addon\_resources\_on\_delete: delete the addon's k8s resources on<br/>                                      removal.<br/>  - configurations:                   list of { key, value } pairs from the<br/>                                      addon's schema (string values; richer<br/>                                      config is JSON-in-a-string).<br/><br/>List the catalog for a version:<br/>  oci ce addon-option list --kubernetes-version <ver> --all --query 'data[*].name' | <pre>map(object({<br/>    version                          = optional(string)<br/>    override_existing                = optional(bool, false)<br/>    remove_addon_resources_on_delete = optional(bool, true)<br/>    configurations = optional(list(object({<br/>      key   = string<br/>      value = string<br/>    })), [])<br/>    timeouts = optional(object({<br/>      create = optional(string, "30m")<br/>      update = optional(string)<br/>      delete = optional(string)<br/>    }), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_addons_to_remove"></a> [addons\_to\_remove](#input\_addons\_to\_remove) | OKE-managed addons to disable, keyed by addon name. Use this to turn off<br/>add-ons that OKE installs by default (e.g. essential add-ons you want to<br/>replace). Requires cluster\_type = "enhanced" and the OCI CLI on the apply<br/>host (the removal runs `oci ce cluster disable-addon` via a local-exec).<br/><br/>Per addon:<br/>  - remove\_k8s\_resources: also delete the addon's Kubernetes resources. | <pre>map(object({<br/>    remove_k8s_resources = optional(bool, true)<br/>  }))</pre> | `{}` | no |
| <a name="input_assign_public_ip_to_control_plane"></a> [assign\_public\_ip\_to\_control\_plane](#input\_assign\_public\_ip\_to\_control\_plane) | Assign a public IP to the control plane endpoint (requires control\_plane\_is\_public). | `bool` | `false` | no |
| <a name="input_cluster_defined_tags"></a> [cluster\_defined\_tags](#input\_cluster\_defined\_tags) | Additional defined tags applied to the cluster only. | `map(string)` | `{}` | no |
| <a name="input_cluster_kms_key_id"></a> [cluster\_kms\_key\_id](#input\_cluster\_kms\_key\_id) | KMS key OCID for Kubernetes secrets encryption. Maps to EKS encryption\_config. The key is not created by this module. | `string` | `null` | no |
| <a name="input_cluster_tags"></a> [cluster\_tags](#input\_cluster\_tags) | Additional freeform tags applied to the cluster only. | `map(string)` | `{}` | no |
| <a name="input_cluster_type"></a> [cluster\_type](#input\_cluster\_type) | OKE cluster tier: "basic" or "enhanced". Enhanced is required for addons and virtual node pools. | `string` | `"basic"` | no |
| <a name="input_cni_type"></a> [cni\_type](#input\_cni\_type) | Pod networking model: "flannel" (FLANNEL\_OVERLAY) or "npn" (OCI\_VCN\_IP\_NATIVE). Loosely maps to the EKS CNI/ip\_family choice. | `string` | `"flannel"` | no |
| <a name="input_compartment_id"></a> [compartment\_id](#input\_compartment\_id) | The compartment OCID in which to create the cluster and node pools. Maps to AWS account/region scoping. | `string` | n/a | yes |
| <a name="input_control_plane_allowed_cidrs"></a> [control\_plane\_allowed\_cidrs](#input\_control\_plane\_allowed\_cidrs) | CIDRs allowed to reach the Kubernetes API server (TCP 6443). Maps to EKS endpoint\_public\_access\_cidrs, but is enforced through the recommended control-plane NSG ruleset rather than the cluster API, so it has no effect unless create\_control\_plane\_nsg and control\_plane\_nsg\_enable\_recommended\_rules are both true. | `list(string)` | `[]` | no |
| <a name="input_control_plane_enabled_log_categories"></a> [control\_plane\_enabled\_log\_categories](#input\_control\_plane\_enabled\_log\_categories) | OKE control-plane log categories to enable. Only takes effect when<br/>create\_control\_plane\_log\_group = true. Maps to EKS enabled\_log\_types, but<br/>OKE's category set is different (no audit/authenticator log type exists<br/>on OKE). Valid values: "kube-apiserver", "kube-controller-manager",<br/>"kube-scheduler", "cloud-controller-manager", "all-service-logs". | `list(string)` | `[]` | no |
| <a name="input_control_plane_is_public"></a> [control\_plane\_is\_public](#input\_control\_plane\_is\_public) | Whether the control plane endpoint is reachable publicly. Maps to EKS endpoint\_public\_access. | `bool` | `false` | no |
| <a name="input_control_plane_log_group_defined_tags"></a> [control\_plane\_log\_group\_defined\_tags](#input\_control\_plane\_log\_group\_defined\_tags) | Defined tags applied to the control-plane log group. | `map(string)` | `{}` | no |
| <a name="input_control_plane_log_group_tags"></a> [control\_plane\_log\_group\_tags](#input\_control\_plane\_log\_group\_tags) | Freeform tags applied to the control-plane log group. | `map(string)` | `{}` | no |
| <a name="input_control_plane_log_retention_duration"></a> [control\_plane\_log\_retention\_duration](#input\_control\_plane\_log\_retention\_duration) | Retention in days for control-plane logs. Null uses the OCI Logging default (30 days). Maps to the EKS control-plane CloudWatch log group's retention\_in\_days. | `number` | `null` | no |
| <a name="input_control_plane_nsg_egress_rules"></a> [control\_plane\_nsg\_egress\_rules](#input\_control\_plane\_nsg\_egress\_rules) | Egress rules for the created control plane NSG, keyed by name. | `any` | `{}` | no |
| <a name="input_control_plane_nsg_enable_recommended_rules"></a> [control\_plane\_nsg\_enable\_recommended\_rules](#input\_control\_plane\_nsg\_enable\_recommended\_rules) | Add the recommended OKE control-plane NSG rules (API/OKE ports 6443/10250/12250, ICMP path discovery, OSN egress, CP inter-comm) to the created cluster NSG. Maps to the EKS node\_security\_group\_enable\_recommended\_rules concept. Only applies when create\_control\_plane\_nsg = true. | `bool` | `true` | no |
| <a name="input_control_plane_nsg_ids"></a> [control\_plane\_nsg\_ids](#input\_control\_plane\_nsg\_ids) | Additional NSG OCIDs for the control plane endpoint. Maps to EKS additional\_security\_group\_ids. | `list(string)` | `[]` | no |
| <a name="input_control_plane_nsg_ingress_rules"></a> [control\_plane\_nsg\_ingress\_rules](#input\_control\_plane\_nsg\_ingress\_rules) | Ingress rules for the created control plane NSG, keyed by name. | `any` | `{}` | no |
| <a name="input_control_plane_subnet_id"></a> [control\_plane\_subnet\_id](#input\_control\_plane\_subnet\_id) | Subnet OCID for the cluster control plane endpoint. Maps to EKS control\_plane\_subnet\_ids. | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources are created (affects all resources in this module). | `bool` | `true` | no |
| <a name="input_create_control_plane_log_group"></a> [create\_control\_plane\_log\_group](#input\_create\_control\_plane\_log\_group) | Create an OCI Logging log group + one log per entry in control\_plane\_enabled\_log\_categories for the cluster's control-plane logs. Maps to EKS create\_cloudwatch\_log\_group. | `bool` | `false` | no |
| <a name="input_create_control_plane_nsg"></a> [create\_control\_plane\_nsg](#input\_create\_control\_plane\_nsg) | Create a generic NSG for the control plane. Rules are supplied via cluster\_nsg\_*\_rules. | `bool` | `false` | no |
| <a name="input_create_worker_nsg"></a> [create\_worker\_nsg](#input\_create\_worker\_nsg) | Create a generic NSG for workers. Rules are supplied via worker\_nsg\_*\_rules. | `bool` | `false` | no |
| <a name="input_defined_tags"></a> [defined\_tags](#input\_defined\_tags) | Defined tags (namespace.key = value) applied to all resources. OCI-only; no AWS equivalent. | `map(string)` | `{}` | no |
| <a name="input_enable_ipv6"></a> [enable\_ipv6](#input\_enable\_ipv6) | Enable IPv4/IPv6 dual-stack on the cluster. Maps to EKS ip\_family = ipv6. | `bool` | `false` | no |
| <a name="input_enable_oidc_discovery"></a> [enable\_oidc\_discovery](#input\_enable\_oidc\_discovery) | Enable the OIDC discovery endpoint (workload identity). Maps loosely to EKS enable\_irsa. | `bool` | `false` | no |
| <a name="input_enable_oidc_token_auth"></a> [enable\_oidc\_token\_auth](#input\_enable\_oidc\_token\_auth) | Enable structured OIDC token authentication on the cluster. | `bool` | `false` | no |
| <a name="input_enable_sensitive_outputs"></a> [enable\_sensitive\_outputs](#input\_enable\_sensitive\_outputs) | Include sensitive detail (kubeconfig, CA cert) in module outputs. | `bool` | `false` | no |
| <a name="input_image_signing_keys"></a> [image\_signing\_keys](#input\_image\_signing\_keys) | KMS key OCIDs used to verify signed images (required when use\_signed\_images = true). | `list(string)` | `[]` | no |
| <a name="input_ip_families"></a> [ip\_families](#input\_ip\_families) | Explicit ip\_families list, overriding enable\_ipv6 (e.g. ["IPv4","IPv6"]). | `list(string)` | `[]` | no |
| <a name="input_kubeproxy_mode"></a> [kubeproxy\_mode](#input\_kubeproxy\_mode) | kube-proxy mode for worker nodes: "iptables" or "ipvs". | `string` | `"iptables"` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version for the cluster, e.g. "v1.30.1". Maps to EKS kubernetes\_version. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the OKE cluster. Maps to the EKS name variable (the cluster\_name output mirrors EKS's output name). | `string` | `"oke"` | no |
| <a name="input_node_pools"></a> [node\_pools](#input\_node\_pools) | Managed node pools keyed by name. Maps to eks\_managed\_node\_groups. | <pre>map(object({<br/>    compartment_id          = optional(string)<br/>    kubernetes_version      = optional(string)<br/>    shape                   = string<br/>    ocpus                   = optional(number, 2)<br/>    memory                  = optional(number, 16)<br/>    size                    = optional(number, 1)<br/>    autoscale               = optional(bool, false)<br/>    image_id                = optional(string)<br/>    boot_volume_size        = optional(number, 50)<br/>    availability_domains    = optional(list(number))<br/>    placement_fds           = optional(list(string))<br/>    subnet_id               = optional(string)<br/>    nsg_ids                 = optional(list(string), [])<br/>    pod_subnet_id           = optional(string)<br/>    pod_nsg_ids             = optional(list(string), [])<br/>    max_pods_per_node       = optional(number, 31)<br/>    node_labels             = optional(map(string), {})<br/>    node_metadata           = optional(map(string), {})<br/>    volume_kms_key_id       = optional(string)<br/>    pv_transit_encryption   = optional(bool, true)<br/>    capacity_reservation_id = optional(string)<br/>    preemptible_config = optional(object({<br/>      enable                  = optional(bool, false)<br/>      is_preserve_boot_volume = optional(bool, false)<br/>    }), {})<br/>    eviction_grace_duration = optional(number, 300)<br/>    force_node_delete       = optional(bool, false)<br/>    force_node_action       = optional(bool, false)<br/>    network_launch_type     = optional(string)<br/>    node_cycling = optional(object({<br/>      enabled             = optional(bool, false)<br/>      maximum_surge       = optional(string, "1")<br/>      maximum_unavailable = optional(string, "1")<br/>      cycle_modes         = optional(list(string), ["BOOT_VOLUME_REPLACE"])<br/>    }), {})<br/>    timeouts = optional(object({<br/>      create = optional(string)<br/>      update = optional(string)<br/>      delete = optional(string, "75m")<br/>    }), {})<br/>    freeform_tags = optional(map(string), {})<br/>    defined_tags  = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_oidc_token_authentication_config"></a> [oidc\_token\_authentication\_config](#input\_oidc\_token\_authentication\_config) | OIDC token authentication settings (issuer\_url, client\_id, ca\_certificate, claims, etc.). | `any` | `{}` | no |
| <a name="input_persistent_volume_defined_tags"></a> [persistent\_volume\_defined\_tags](#input\_persistent\_volume\_defined\_tags) | Defined tags applied to persistent volumes provisioned by the cluster. | `map(string)` | `{}` | no |
| <a name="input_persistent_volume_tags"></a> [persistent\_volume\_tags](#input\_persistent\_volume\_tags) | Freeform tags applied to persistent volumes provisioned by the cluster. | `map(string)` | `{}` | no |
| <a name="input_pod_nsg_ids"></a> [pod\_nsg\_ids](#input\_pod\_nsg\_ids) | Default pod NSG OCIDs for npn node pools. | `list(string)` | `[]` | no |
| <a name="input_pod_subnet_id"></a> [pod\_subnet\_id](#input\_pod\_subnet\_id) | Default pod subnet OCID for npn node pools. | `string` | `null` | no |
| <a name="input_pods_cidr"></a> [pods\_cidr](#input\_pods\_cidr) | CIDR block for pods (flannel only). Maps loosely to EKS pod networking. | `string` | `"10.244.0.0/16"` | no |
| <a name="input_self_managed_node_pools"></a> [self\_managed\_node\_pools](#input\_self\_managed\_node\_pools) | Self-managed node pools (instance pools) keyed by name. Maps to self\_managed\_node\_groups. | <pre>map(object({<br/>    compartment_id        = optional(string)<br/>    kubernetes_version    = optional(string)<br/>    cloud_init            = optional(string)<br/>    shape                 = string<br/>    ocpus                 = optional(number, 2)<br/>    memory                = optional(number, 16)<br/>    size                  = optional(number, 1)<br/>    autoscale             = optional(bool, false)<br/>    image_id              = optional(string)<br/>    boot_volume_size      = optional(number, 50)<br/>    availability_domains  = optional(list(number))<br/>    placement_fds         = optional(list(string))<br/>    subnet_id             = optional(string)<br/>    nsg_ids               = optional(list(string), [])<br/>    assign_public_ip      = optional(bool, false)<br/>    node_labels           = optional(map(string), {})<br/>    volume_kms_key_id     = optional(string)<br/>    pv_transit_encryption = optional(bool, true)<br/>    node_metadata         = optional(map(string), {})<br/>    freeform_tags         = optional(map(string), {})<br/>    defined_tags          = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_service_lb_backend_nsg_ids"></a> [service\_lb\_backend\_nsg\_ids](#input\_service\_lb\_backend\_nsg\_ids) | NSG OCIDs applied to service load balancer backends. | `list(string)` | `[]` | no |
| <a name="input_service_lb_defined_tags"></a> [service\_lb\_defined\_tags](#input\_service\_lb\_defined\_tags) | Defined tags applied to service load balancers provisioned by the cluster. | `map(string)` | `{}` | no |
| <a name="input_service_lb_subnet_id"></a> [service\_lb\_subnet\_id](#input\_service\_lb\_subnet\_id) | Subnet OCID for service load balancers. No direct EKS equivalent (EKS uses tagged subnets). | `string` | n/a | yes |
| <a name="input_service_lb_tags"></a> [service\_lb\_tags](#input\_service\_lb\_tags) | Freeform tags applied to service load balancers provisioned by the cluster. | `map(string)` | `{}` | no |
| <a name="input_services_cidr"></a> [services\_cidr](#input\_services\_cidr) | CIDR block for Kubernetes services (ClusterIP). Maps to EKS service\_ipv4\_cidr. | `string` | `"10.96.0.0/16"` | no |
| <a name="input_ssh_authorized_keys"></a> [ssh\_authorized\_keys](#input\_ssh\_authorized\_keys) | SSH public key authorized on worker nodes. Maps to EKS remote\_access keys. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Freeform tags applied to all resources. Maps to the AWS tags variable. | `map(string)` | `{}` | no |
| <a name="input_timeouts"></a> [timeouts](#input\_timeouts) | Create/update/delete timeouts for the cluster. | <pre>object({<br/>    create = optional(string, "60m")<br/>    update = optional(string, "120m")<br/>    delete = optional(string, "60m")<br/>  })</pre> | `{}` | no |
| <a name="input_use_signed_images"></a> [use\_signed\_images](#input\_use\_signed\_images) | Enforce signed worker node images via an image policy. | `bool` | `false` | no |
| <a name="input_vcn_id"></a> [vcn\_id](#input\_vcn\_id) | OCID of the VCN hosting the cluster. Maps to the EKS vpc\_id variable. Supplied by the sibling terraform-oci-vcn module. | `string` | n/a | yes |
| <a name="input_virtual_node_pools"></a> [virtual\_node\_pools](#input\_virtual\_node\_pools) | Virtual (serverless) node pools keyed by name. Requires enhanced cluster + npn CNI. Maps to fargate\_profiles. | <pre>map(object({<br/>    compartment_id       = optional(string)<br/>    shape                = optional(string, "Pod.Standard.E4.Flex")<br/>    size                 = optional(number, 1)<br/>    availability_domains = optional(list(number))<br/>    subnet_id            = optional(string)<br/>    pod_subnet_id        = optional(string)<br/>    nsg_ids              = optional(list(string), [])<br/>    pod_nsg_ids          = optional(list(string), [])<br/>    node_labels          = optional(map(string), {})<br/>    taints = optional(map(object({<br/>      value  = optional(string)<br/>      effect = optional(string, "NoSchedule")<br/>    })), {})<br/>    timeouts = optional(object({<br/>      create = optional(string)<br/>      update = optional(string)<br/>      delete = optional(string, "75m")<br/>    }), {})<br/>    freeform_tags = optional(map(string), {})<br/>    defined_tags  = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_worker_allow_internet_egress"></a> [worker\_allow\_internet\_egress](#input\_worker\_allow\_internet\_egress) | Add an all-protocol egress-to-internet (0.0.0.0/0) rule to the recommended worker NSG ruleset. Set false for private clusters that reach the internet only via a NAT/service gateway. | `bool` | `true` | no |
| <a name="input_worker_defined_tags"></a> [worker\_defined\_tags](#input\_worker\_defined\_tags) | Defined tags applied to all worker pools (merged with var.defined\_tags). | `map(string)` | `{}` | no |
| <a name="input_worker_metadata"></a> [worker\_metadata](#input\_worker\_metadata) | Global instance metadata merged into every node pool (per-pool node\_metadata is merged on top). | `map(string)` | `{}` | no |
| <a name="input_worker_nsg_egress_rules"></a> [worker\_nsg\_egress\_rules](#input\_worker\_nsg\_egress\_rules) | Egress rules for the created worker NSG, keyed by name. | `any` | `{}` | no |
| <a name="input_worker_nsg_enable_recommended_rules"></a> [worker\_nsg\_enable\_recommended\_rules](#input\_worker\_nsg\_enable\_recommended\_rules) | Add the recommended OKE worker NSG rules (node-to-node, control-plane comms, ICMP path discovery, OSN egress) to the created worker NSG. Maps to the EKS node\_security\_group\_enable\_recommended\_rules concept. Only applies when create\_worker\_nsg = true. | `bool` | `true` | no |
| <a name="input_worker_nsg_ids"></a> [worker\_nsg\_ids](#input\_worker\_nsg\_ids) | Default NSG OCIDs for worker node VNICs. Maps to EKS node security groups. | `list(string)` | `[]` | no |
| <a name="input_worker_nsg_ingress_rules"></a> [worker\_nsg\_ingress\_rules](#input\_worker\_nsg\_ingress\_rules) | Ingress rules for the created worker NSG, keyed by name. | `any` | `{}` | no |
| <a name="input_worker_subnet_id"></a> [worker\_subnet\_id](#input\_worker\_subnet\_id) | Default worker subnet OCID for node pools. Maps to EKS subnet\_ids. | `string` | `null` | no |
| <a name="input_worker_tags"></a> [worker\_tags](#input\_worker\_tags) | Freeform tags applied to all worker pools (merged with var.tags). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_apiserver_private_host"></a> [apiserver\_private\_host](#output\_apiserver\_private\_host) | Private API server host address. |
| <a name="output_cluster_addons"></a> [cluster\_addons](#output\_cluster\_addons) | OKE-managed addons by name. Maps to cluster\_addons. |
| <a name="output_cluster_all_attributes"></a> [cluster\_all\_attributes](#output\_cluster\_all\_attributes) | All attributes of the cluster resource. |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Base64 cluster CA certificate. Only populated when enable\_sensitive\_outputs = true. |
| <a name="output_cluster_endpoints"></a> [cluster\_endpoints](#output\_cluster\_endpoints) | Public/private endpoints of the cluster. Maps to EKS cluster\_endpoint. |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | OCID of the OKE cluster. Maps to EKS cluster\_id. |
| <a name="output_cluster_ip_families"></a> [cluster\_ip\_families](#output\_cluster\_ip\_families) | Resolved IP families for the cluster (e.g. ["IPv4"] or ["IPv4", "IPv6"]).<br/>EKS's analog output, cluster\_ip\_family, is a single value; OCI's<br/>ip\_families is a list, so this output stays plural and list-typed to match<br/>the OCI API rather than force a misleading singular name. |
| <a name="output_cluster_kubernetes_version"></a> [cluster\_kubernetes\_version](#output\_cluster\_kubernetes\_version) | Kubernetes version of the cluster. Maps to EKS cluster\_version. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the OKE cluster. Maps to EKS cluster\_name. |
| <a name="output_cluster_oidc_discovery_endpoint"></a> [cluster\_oidc\_discovery\_endpoint](#output\_cluster\_oidc\_discovery\_endpoint) | OIDC discovery endpoint (workload identity). Maps to EKS oidc\_provider. |
| <a name="output_cluster_service_cidr"></a> [cluster\_service\_cidr](#output\_cluster\_service\_cidr) | Resolved Kubernetes service CIDR block. Maps to EKS cluster\_service\_cidr. |
| <a name="output_cluster_state"></a> [cluster\_state](#output\_cluster\_state) | Lifecycle state of the cluster. Maps to EKS cluster\_status. |
| <a name="output_control_plane_log_group_id"></a> [control\_plane\_log\_group\_id](#output\_control\_plane\_log\_group\_id) | OCID of the control-plane log group created by this module (null when create\_control\_plane\_log\_group = false). Maps to EKS cloudwatch\_log\_group\_arn. |
| <a name="output_control_plane_log_ids"></a> [control\_plane\_log\_ids](#output\_control\_plane\_log\_ids) | Control-plane log OCIDs by category. |
| <a name="output_control_plane_nsg_id"></a> [control\_plane\_nsg\_id](#output\_control\_plane\_nsg\_id) | OCID of the control plane NSG created by this module (null when create\_control\_plane\_nsg = false). |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Cluster kubeconfig content. Only populated when enable\_sensitive\_outputs = true. |
| <a name="output_node_pool_ids"></a> [node\_pool\_ids](#output\_node\_pool\_ids) | Managed node pool OCIDs by name. |
| <a name="output_node_pools"></a> [node\_pools](#output\_node\_pools) | Managed node pools by name. Maps to eks\_managed\_node\_groups. |
| <a name="output_self_managed_node_pool_ids"></a> [self\_managed\_node\_pool\_ids](#output\_self\_managed\_node\_pool\_ids) | Self-managed instance pool OCIDs by name. |
| <a name="output_self_managed_node_pools"></a> [self\_managed\_node\_pools](#output\_self\_managed\_node\_pools) | Self-managed node pools (instance pools) by name. Maps to self\_managed\_node\_groups. |
| <a name="output_virtual_node_pool_ids"></a> [virtual\_node\_pool\_ids](#output\_virtual\_node\_pool\_ids) | Virtual node pool OCIDs by name. |
| <a name="output_virtual_node_pools"></a> [virtual\_node\_pools](#output\_virtual\_node\_pools) | Virtual node pools by name. Maps to fargate\_profiles. |
| <a name="output_worker_nsg_id"></a> [worker\_nsg\_id](#output\_worker\_nsg\_id) | OCID of the worker NSG created by this module (null when create\_worker\_nsg = false). |
<!-- END_TF_DOCS -->

## License

Apache 2.0. See [LICENSE](LICENSE).
