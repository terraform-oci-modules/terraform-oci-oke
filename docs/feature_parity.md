# EKS to OKE feature parity and gap analysis

This module is the OCI Kubernetes counterpart of
[`terraform-aws-eks`](https://github.com/terraform-aws-modules/terraform-aws-eks).
It mirrors that module's **scope** (cluster + node groups + managed add-ons, with
networking supplied as input) and maps each concept to its idiomatic OKE
equivalent. Networking is delegated to the sibling
[`terraform-oci-vcn`](../../terraform-oci-vcn) module.

> **Validated against `terraform-aws-eks` v21.24.2** (latest release at the time
> of writing). Nothing in v21.24.1 or v21.24.2 changed the parity picture: both
> are CI/pre-commit housekeeping plus a Windows SSM parameter-path fix, and
> Windows nodes are not an OKE concept. The last two functional EKS additions,
> `control_plane_egress_mode` (#3728) and the EC2 `nested_virtualization` CPU
> option (#3686), are AWS-provider-specific with no OCI counterpart.

This document is deliberately blunt about what is **not** here. Read it as three
separate questions:

1. What maps cleanly? See [Resource mapping](#resource-mapping),
   [Variable mapping](#variable-mapping), [Output mapping](#output-mapping).
2. What is missing because the cloud is different? See
   [Gap class A](#gap-class-a-no-oke-equivalent-exists).
3. What is missing because this module chose not to build it, or has not built
   it yet? See [Gap class B](#gap-class-b-deliberate-scope-exclusions) and
   [Gap class C](#gap-class-c-oke-capability-not-yet-exposed-real-backlog).

Gap class C is the only list that is an actual backlog. A and B are settled
design positions.

## Resource mapping

| EKS (AWS)                          | OKE (OCI)                                                                                       | Notes                                             |
| ---------------------------------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| `aws_eks_cluster`                  | `oci_containerengine_cluster`                                                                   | `cluster_type` selects `BASIC` vs `ENHANCED`      |
| `aws_eks_node_group`               | `oci_containerengine_node_pool` (`modules/node-pool`)                                           | managed worker nodes                              |
| `aws_eks_fargate_profile`          | `oci_containerengine_virtual_node_pool` (`modules/virtual-node-pool`)                           | serverless pods; enhanced + npn only              |
| `aws_autoscaling_group` + launch template | `oci_core_instance_configuration` + `oci_core_instance_pool` (`modules/self-managed-node-pool`) | nodes self-join via cloud-init metadata           |
| `aws_eks_addon`                    | `oci_containerengine_addon`                                                                     | enhanced clusters only                            |
| `aws_eks_identity_provider_config` | `options.open_id_connect_token_authentication_config`                                           | inline on the cluster, not a separate resource    |
| `aws_security_group` (cluster/node) | `oci_core_network_security_group` (optional)                                                   | see [Network security groups](#network-security-groups) |
| `aws_eks_access_entry` / `_access_policy_association` | none                                                                          | OKE authorizes through OCI IAM ([class A](#gap-class-a-no-oke-equivalent-exists)) |
| `aws_iam_role` / `aws_iam_openid_connect_provider` | none                                                                          | IAM is documented, not created ([class B](#gap-class-b-deliberate-scope-exclusions)) |
| `aws_kms_key` / `aws_kms_alias`    | none                                                                                            | pass an existing Vault key OCID ([class B](#gap-class-b-deliberate-scope-exclusions)) |
| `aws_cloudwatch_log_group`         | `oci_logging_log_group` + `oci_logging_log`                                                     | control-plane logging, off by default            |

### Submodule mapping

| `terraform-aws-eks` submodule | This module                       | Status                                                        |
| ----------------------------- | --------------------------------- | ------------------------------------------------------------- |
| `eks-managed-node-group`      | `modules/node-pool`               | present                                                       |
| `fargate-profile`             | `modules/virtual-node-pool`       | present                                                       |
| `self-managed-node-group`     | `modules/self-managed-node-pool`  | present                                                       |
| `_user_data`                  | none                              | folded into the node pool modules (`node_metadata`/`cloud_init`) |
| `karpenter`                   | none                              | class A: Karpenter has no OCI provider, see below             |
| `hybrid-node-role`            | none                              | class A: no OKE hybrid/on-prem node feature                   |
| `capability`                  | none                              | class A: EKS-specific IAM plumbing for ACK/ArgoCD capabilities |

## Variable mapping

### Cluster

| EKS variable                                          | OKE variable                                                                 | Notes                                       |
| ----------------------------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------- |
| `create`                                              | `create`                                                                     |                                             |
| `name`                                                | `name`                                                                       | the `cluster_name` **output** mirrors EKS's output name |
| `kubernetes_version`                                  | `kubernetes_version`                                                         | OKE requires a `v` prefix, e.g. `v1.36.1`. Required here; EKS lets AWS pick the latest when null, the OCI provider does not |
| `region`                                              | provider `region`                                                            | OCI has no per-resource region argument     |
| (no equivalent)                                       | `compartment_id`                                                             | OCI's account/region scoping analog, OKE-specific |
| `tags`                                                | `tags` (freeform) + `defined_tags`                                           | OCI has two tag systems                     |
| `cluster_tags`                                        | `cluster_tags` / `cluster_defined_tags`                             |                                             |
| `timeouts`                                            | `timeouts`                                                           |                                             |
| `encryption_config` + `create_kms_key`                | `cluster_kms_key_id`                                                         | key is **not** created here                 |
| `attach_encryption_policy`, `encryption_policy_*`     | none                                                                          | IAM policy plumbing for the encryption key, [class B](#gap-class-b-deliberate-scope-exclusions) |
| `service_ipv4_cidr`                                   | `services_cidr`                                                              |                                             |
| (no equivalent)                                       | `pods_cidr`                                                                  | flannel overlay CIDR, OKE-specific          |
| `ip_family`                                           | `enable_ipv6` / `ip_families`                                                |                                             |
| `enable_irsa`, `openid_connect_audiences`             | `enable_oidc_discovery`                                                     | OKE workload identity                       |
| `identity_providers`                                  | `enable_oidc_token_auth` + `oidc_token_authentication_config`               | inline on the cluster                       |
| `addons`, `addons_timeouts`                           | `addons` (per-addon `timeouts`)                                              | enhanced clusters only                      |
| (no equivalent)                                       | `addons_to_remove`                                                           | disables OKE-default add-ons, OKE-specific  |
| (no equivalent)                                       | `use_signed_images` / `image_signing_keys`                                   | OKE image policy, OKE-specific              |
| (no equivalent)                                       | `kubeproxy_mode`                                                             | `iptables` or `ipvs`, OKE-specific          |
| `putin_khuylo`                                        | none                                                                         | not ported                                  |
| `create_cloudwatch_log_group`                         | `create_control_plane_log_group`                                             |                                             |
| `enabled_log_types`                                   | `control_plane_enabled_log_categories`                                       | OKE's category set differs from EKS's `api`/`audit`/`authenticator`/`controllerManager`/`scheduler` - no audit or authenticator log type exists on OKE |
| `cloudwatch_log_group_retention_in_days`              | `control_plane_log_retention_duration`                                       |                                             |
| (no equivalent)                                       | `control_plane_log_group_tags` / `control_plane_log_group_defined_tags`      | OKE-specific per-resource tags               |

### Networking

| EKS variable                                                    | OKE variable                                                   | Notes                                                     |
| --------------------------------------------------------------- | -------------------------------------------------------------- | --------------------------------------------------------- |
| `vpc_id`                                                        | `vcn_id`                                                       |                                                           |
| `subnet_ids`                                                    | `worker_subnet_id` (+ `pod_subnet_id` for npn)                 | OKE takes one subnet, not a list; per-pool override exists |
| `control_plane_subnet_ids`                                      | `control_plane_subnet_id`                                      |                                                           |
| `endpoint_public_access`                                        | `control_plane_is_public` + `assign_public_ip_to_control_plane` | OKE splits reachability from public-IP assignment          |
| `endpoint_private_access`                                       | always on                                                      | OKE's private endpoint cannot be disabled                  |
| `endpoint_public_access_cidrs`                                  | `control_plane_allowed_cidrs`                                  | applied through the created cluster NSG, not the cluster API |
| `additional_security_group_ids`                                 | `control_plane_nsg_ids`                                        |                                                           |
| `create_security_group` / `security_group_*`                    | `create_control_plane_nsg` / `control_plane_nsg_*_rules`                   |                                                           |
| `create_node_security_group` / `node_security_group_*`          | `create_worker_nsg` / `worker_nsg_*_rules`                     |                                                           |
| `create_primary_security_group_tags`                             | none                                                            | tags the SG the EKS **service** auto-creates; OKE creates no such cluster-managed SG |
| `service_ipv6_cidr`                                              | none                                                            | AWS itself does not let you set a custom value either (always `fc00::/7`); OKE's IPv6 service range is likewise platform-assigned |
| `node_security_group_enable_recommended_rules`                  | `control_plane_nsg_enable_recommended_rules` / `worker_nsg_enable_recommended_rules` | split across both tiers here            |
| (no equivalent, EKS uses subnet tags)                           | `service_lb_subnet_id`, `service_lb_backend_nsg_ids`                      | see [service_load_balancers.md](service_load_balancers.md) |
| (no equivalent)                                                 | `pod_nsg_ids`, `worker_nsg_ids`                                | pass-through of externally built NSGs                      |

### Node groups / node pools

| EKS variable                | OKE variable              |
| --------------------------- | ------------------------- |
| `eks_managed_node_groups`   | `node_pools`              |
| `fargate_profiles`          | `virtual_node_pools`      |
| `self_managed_node_groups`  | `self_managed_node_pools` |

Per-pool attributes, comparing `terraform-aws-eks`'s `eks-managed-node-group`
submodule with this module's `node_pools` object type:

| EKS node group attribute                            | OKE node pool attribute                          | Notes                                                        |
| ---------------------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------ |
| `instance_types`                                     | `shape` (+ `ocpus` / `memory` for Flex shapes)   | OKE takes exactly one shape per pool, not a list             |
| `min_size` / `max_size` / `desired_size`             | `size` + `autoscale`                             | OKE node pools have a single `size`; min/max live in the ClusterAutoscaler add-on config, not the pool. `autoscale = true` makes Terraform stop reconciling `size` |
| `subnet_ids`                                         | `subnet_id`                                      | one subnet per pool; spread across ADs via `availability_domains` |
| `ami_id` / `ami_type` / `ami_release_version`        | `image_id` (auto-resolved when unset)            | resolved from Kubernetes version + shape architecture + GPU class |
| `disk_size`                                          | `boot_volume_size`                               |                                                              |
| `labels`                                             | `node_labels`                                    |                                                              |
| `taints`                                             | **not available on managed pools**               | `oci_containerengine_node_pool` has no taints argument. Available on `virtual_node_pools` only. See [class A](#gap-class-a-no-oke-equivalent-exists) |
| `capacity_type = "SPOT"`                             | `preemptible_config`                             |                                                              |
| `capacity_reservation_specification`                 | `capacity_reservation_id`                        | OKE requires a single AD when set (enforced by a precondition) |
| `update_config`                                      | `node_cycling`                                   | `maximum_surge` / `maximum_unavailable` / `cycle_modes`; requires `cluster_type = "enhanced"`, see [docs/upgrades.md](upgrades.md) |
| `remote_access` / `key_name`                         | `ssh_authorized_keys` (cluster-wide)             | OKE sets the key per pool from one cluster-level input       |
| `vpc_security_group_ids`                             | `nsg_ids`                                        |                                                              |
| `pre_bootstrap_user_data`, `post_bootstrap_user_data`, `bootstrap_extra_args`, `cloudinit_pre_nodeadm` | `node_metadata` (managed) / `cloud_init` (self-managed), with cluster-wide defaults from the root `worker_metadata` | OKE managed pools accept metadata, not a rendered user-data template |
| `timeouts`                                           | `timeouts` (`create`/`update`/`delete`, `delete` defaults `"75m"`) |                                                              |
| `block_device_mappings`                              | `boot_volume_size`, `volume_kms_key_id`, `pv_transit_encryption` | OKE managed pools expose only the boot volume            |
| `enable_monitoring`, `enclave_options`, `metadata_options`, `credit_specification`, `cpu_options`, `license_specifications`, `maintenance_options`, `network_performance_options`, `placement`, `instance_market_options`, `enable_efa_support` | none | EC2 launch-template surface with no `oci_containerengine_node_pool` counterpart |
| `create_iam_role` / `iam_role_*` / `node_iam_role_*` | none                                             | [class B](#gap-class-b-deliberate-scope-exclusions)          |
| `node_repair_config`                                 | none                                             | no OKE equivalent; closest is the `NodeProblemDetector` add-on |
| `force_update_version`                               | none                                             | no OKE equivalent                                            |
| (no equivalent)                                      | `eviction_grace_duration`, `force_node_delete`, `force_node_action` | OKE drain-on-delete controls, OKE-specific. `force_node_action` maps to `is_force_action_after_grace_duration` |
| (no equivalent)                                      | `max_pods_per_node`, `pod_subnet_id`, `pod_nsg_ids` | npn CNI only, OKE-specific                                |
| (no equivalent)                                      | `placement_fds`                                  | OCI fault domains, no EC2 analog                             |
| (no equivalent)                                      | `network_launch_type`                            | advanced provider-validated override, OKE-specific           |

## Output mapping

| EKS output                                       | OKE output                                       | Notes                                                    |
| ------------------------------------------------ | ------------------------------------------------ | -------------------------------------------------------- |
| `cluster_id` / `cluster_arn`                     | `cluster_id`                                     | an OCID is both the id and the ARN analog                |
| `cluster_name`                                   | `cluster_name`                                   |                                                          |
| `cluster_version`                                | `cluster_kubernetes_version`                     |                                                          |
| `cluster_endpoint`                               | `cluster_endpoints`                              | OKE returns public *and* private endpoints in one object |
| `cluster_status`                                 | `cluster_state`                                  |                                                          |
| `cluster_certificate_authority_data`             | `cluster_ca_certificate`                         | gated behind `enable_sensitive_outputs = true`                      |
| `cluster_oidc_issuer_url`, `oidc_provider`       | `cluster_oidc_discovery_endpoint`                |                                                          |
| `cluster_addons`                                 | `cluster_addons`                                 |                                                          |
| `eks_managed_node_groups`                        | `node_pools` / `node_pool_ids`                   |                                                          |
| `fargate_profiles`                               | `virtual_node_pools` / `virtual_node_pool_ids`   |                                                          |
| `self_managed_node_groups`                       | `self_managed_node_pools` / `self_managed_node_pool_ids` |                                                  |
| `self_managed_node_groups_autoscaling_group_names` | `self_managed_node_pool_ids`                   | the instance pool OCID is the ASG-name analog            |
| `eks_managed_node_groups_autoscaling_group_names`  | none                                             | managed node pools have no separate ASG-like resource to name; unlike self-managed pools there is nothing to map |
| `cluster_security_group_id` / `cluster_security_group_arn` | `control_plane_nsg_id`                    | null unless `create_control_plane_nsg = true`; one OCID serves as both id and ARN analog |
| `node_security_group_id` / `node_security_group_arn` | `worker_nsg_id`                                | null unless `create_worker_nsg = true`; one OCID serves as both id and ARN analog |
| `cluster_identity_providers`                     | via `cluster_all_attributes`                     | OIDC token auth config is set through `oidc_token_authentication_config`; no dedicated output |
| `cluster_service_cidr`                           | `cluster_service_cidr`                           |                                                          |
| `cluster_ip_family`                              | `cluster_ip_families`                            | EKS's is a single value; OCI's `ip_families` is a list, so this output stays plural |
| (no equivalent)                                  | `kubeconfig`                                     | EKS expects you to build it from endpoint + CA           |
| (no equivalent)                                  | `apiserver_private_host`                         | OKE-specific, consumed by node pools                     |
| `cluster_primary_security_group_id`              | none                                             | OKE creates no cluster-managed security group            |
| `cluster_platform_version`                       | none                                             | no OKE concept                                           |
| `cluster_tls_certificate_sha1_fingerprint`       | none                                             | only needed for the IRSA OIDC provider AWS resource      |
| `cluster_dualstack_oidc_issuer_url`              | none                                             | OKE has one discovery endpoint                           |
| `access_entries`, `access_policy_associations`   | none                                             | [class A](#gap-class-a-no-oke-equivalent-exists)         |
| `kms_key_*`, `cluster_iam_role_*`, `node_iam_role_*`, `oidc_provider_arn` | none    | [class B](#gap-class-b-deliberate-scope-exclusions)      |
| `cloudwatch_log_group_arn`                       | `control_plane_log_group_id`                     | null unless `create_control_plane_log_group = true` |
| (no equivalent)                                  | `control_plane_log_ids`                          | per-category log OCIDs, OKE-specific                     |
| `cluster_control_plane_scaling_tier`             | none                                             | `cluster_type` (basic/enhanced) is the nearest concept, already an input |

## Gap class A: no OKE equivalent exists

These EKS features cannot be ported. They are AWS-platform constructs with no
OCI counterpart, so the corresponding variables are intentionally absent rather
than stubbed.

| EKS feature                                                                              | Why it does not port                                                                                                                                        |
| ----------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `access_entries`, `enable_cluster_creator_admin_permissions`, `authentication_mode`      | OKE has no in-cluster authorization mapping table. Kubernetes RBAC subjects are OCI IAM users/groups directly; there is no `aws-auth` or access-entry object. |
| `compute_config`, `enable_auto_mode_custom_tags`, `create_auto_mode_iam_resources`, `create_node_iam_role` | EKS Auto Mode has no OKE equivalent. Virtual node pools cover the serverless-pod half, but not the auto-provisioned-node half. `create_node_iam_role` gates the Auto Mode node IAM role specifically, not the per-node-group role covered below.                |
| `control_plane_scaling_config`, `upgrade_policy`                                         | OKE has no control-plane scaling tier and no extended-support policy. `cluster_type` (basic/enhanced) is a feature tier, not a scaling one.                   |
| `remote_network_config`, `modules/hybrid-node-role`                                      | No OKE hybrid/on-premises node feature.                                                                                                                      |
| `zonal_shift_config`                                                                     | No ARC zonal shift equivalent in OCI.                                                                                                                        |
| `outpost_config`                                                                         | OCI Dedicated Region / Compute Cloud@Customer is a whole-region construct, not a per-cluster argument.                                                        |
| `deletion_protection`                                                                    | `oci_containerengine_cluster` has no such argument. Use `lifecycle { prevent_destroy = true }` in your root module.                                           |
| `control_plane_egress_mode`, `create_cni_ipv6_iam_policy`, `include_oidc_root_ca_thumbprint`, `custom_oidc_thumbprints` | AWS-provider-specific plumbing.                                                                        |
| `dataplane_wait_duration`                                                                | Exists because EKS IAM propagation is eventually consistent. The OKE equivalent problem does not occur.                                                       |
| `prefix_separator`, `*_use_name_prefix`                                                  | OCI resource names are not globally unique and need no `name_prefix`/`create_before_destroy` dance.                                                           |
| `modules/karpenter`                                                                      | Karpenter has no OCI cloud provider. Node autoscaling on OKE is the `ClusterAutoscaler` add-on.                                                               |
| `modules/capability`                                                                     | EKS "capabilities" (ACK, ArgoCD) are IAM-role plumbing specific to EKS.                                                                                       |
| `taints` on managed node groups                                                          | **Real functional gap.** `oci_containerengine_node_pool` genuinely has no taints argument (only `initial_node_labels`). Taint managed nodes with a kubelet `--register-with-taints` flag through `node_metadata`, or apply taints post-join with `kubectl`. Virtual node pools do support `taints` natively. |
| `node_repair_config`, `force_update_version`                                             | No provider arguments exist.                                                                                                                                 |

## Gap class B: deliberate scope exclusions

OCI *can* do these; this module chooses not to, to stay compartment-scoped and
match the `terraform-oci-compute-instance` / `terraform-oci-vcn` sibling
convention. Each has a documented path to do it yourself.

- **No IAM creation.** EKS creates the cluster role, node role, and the IRSA
  OIDC provider. This module creates none of that: no
  `oci_identity_dynamic_group`, no `oci_identity_policy`. That keeps it free of
  a home-region provider and tenancy-level permissions. The exact statements
  each feature needs (`cluster_kms_key_id`, `ClusterAutoscaler`, self-managed
  node join, workload identity, `Service` of `type: LoadBalancer`) are in the
  README's **Required IAM** table, to apply out of band. Verify they exist in
  your tenancy rather than assuming, see
  [service_load_balancers.md](service_load_balancers.md).
- **No KMS key creation.** EKS has a family of `kms_key_*` variables (including
  `enable_kms_key_rotation`) plus `attach_encryption_policy` /
  `encryption_policy_*` for the IAM policy that lets the cluster role use the
  key; this module has `cluster_kms_key_id` and per-pool `volume_kms_key_id` /
  `image_signing_keys`. Create the Vault + key with a dedicated module and pass
  the OCIDs.
- **No networking creation.** Subnets, gateways, route tables, and the full
  OKE-recommended security rules come from `terraform-oci-vcn`. This module
  creates at most two convenience NSGs, see below.
- **No log destination creation.** See class C for the one piece of this that is
  a backlog item rather than a settled exclusion.
- **No secondary VNICs on managed node pools.** `oci_containerengine_node_pool`
  has a `secondary_vnics` block in the provider schema (multi-NIC workers,
  analogous to `network_interfaces` in the EKS launch template), but it is
  confirmed non-functional as of provider `oracle/oci` 8.15.0: the API rejects
  it outright on Flannel Overlay clusters ("not allowed for Flannel Overlay"),
  and on npn (`OCI_VCN_IP_NATIVE`) clusters it either rejects the pool
  (`pod_subnet_ids`/`pod_nsg_ids`/`max_pods_per_node` combined with
  `secondary_vnics` is an explicit API error) or, if those fields are left
  unset, accepts the pool but the nodes then fail with "pod network
  configuration timeout" because npn pods have no subnet to get IPs from.
  There is no combination that produces a working pool today. Verified via
  live apply against a real cluster; not merged. Worth revisiting if a future
  provider/OCI release changes this behavior.

## Gap class C: OKE capability not yet exposed (real backlog)

These are the only genuine to-dos: cases where the OCI provider supports a
capability and the EKS module has an analog, but this module has not wired it
up yet. Empty as of this writing - the last item, control-plane logging, is
now implemented (`create_control_plane_log_group`,
`control_plane_enabled_log_categories`, see the variable/output mapping
tables above).

Everything else on `oci_containerengine_cluster`,
`oci_containerengine_node_pool`, and `oci_containerengine_virtual_node_pool` is
either exposed by this module or deliberately skipped as dead: the cluster's
`options.add_ons` block (Kubernetes Dashboard / Tiller, superseded by
`addons`), `options.admission_controller_options` (PodSecurityPolicy,
removed from Kubernetes in 1.25 and inert on every version this module
supports), and the node pool's legacy `subnet_ids` / `quantity_per_subnet` /
`node_image_name` arguments (superseded by `node_config_details`).

## Network security groups

EKS creates a cluster security group and a node security group, each with a
recommended ruleset, and lets you bolt on `*_additional_rules`. This module
mirrors that shape but defaults the creation flags **off**, because the intended
source of NSGs is the sibling `terraform-oci-vcn` module:

- `create_control_plane_nsg` / `create_worker_nsg` (both default `false`) create a
  control-plane NSG and a worker NSG.
- When created, each is seeded with a **recommended OKE ruleset**: control-plane
  to worker to pod communication on `6443` (kube-apiserver), `10250` (kubelet),
  and `12250` (OKE), ICMP type 3 code 4 path-MTU discovery, egress to the Oracle
  Services Network, and (by default) worker egress to the internet. This is the
  OKE analog of `node_security_group_enable_recommended_rules`, split in two:
  `control_plane_nsg_enable_recommended_rules` and
  `worker_nsg_enable_recommended_rules`, both default `true`.
- `control_plane_allowed_cidrs` restricts who may reach the API server on
  `6443`, the analog of `endpoint_public_access_cidrs`. Unlike EKS, where this is
  a cluster API argument, here it is enforced purely by the NSG ruleset, so it is
  a **no-op unless both `create_control_plane_nsg = true` and
  `control_plane_nsg_enable_recommended_rules = true`**. Otherwise restrict API access
  in whichever NSG or security list you pass in instead.
- `worker_allow_internet_egress = false` drops the blanket egress rule for
  private clusters that reach out only via NAT/service gateway.
- Extra rules go in through `control_plane_nsg_ingress_rules` /
  `control_plane_nsg_egress_rules` / `worker_nsg_ingress_rules` /
  `worker_nsg_egress_rules`, the analog of `*_security_group_additional_rules`.
- Pod-tier rules are added only for `cni_type = "npn"` when `pod_nsg_ids` is
  supplied.

These NSGs are a convenience for standalone use and for the `examples/`, which
need them because `terraform-oci-vcn` defaults `lockdown_default_security_list = true`
(deny-all on the VCN's default security list). They are **not** a replacement
for the full, tiered OKE ruleset that `terraform-oci-vcn` models.

## Other intentional differences

- **CNI choice is explicit.** `cni_type = "flannel"` (FLANNEL_OVERLAY) or
  `"npn"` (OCI_VCN_IP_NATIVE). npn requires a pod subnet and is mandatory for
  virtual node pools. EKS has no equivalent switch (VPC CNI is the default and
  alternatives are add-on territory).
- **Add-ons are a fixed, enhanced-only catalog.** Like EKS managed add-ons,
  `addons` enables OKE-managed components, but only on
  `cluster_type = "enhanced"`, and config is limited to the `{ key, value }`
  pairs OKE defines per add-on (no Helm-values equivalent, richer settings go in
  as JSON encoded into a string). Essential add-ons (`CoreDNS`, `KubeProxy`, the
  CNI) are always managed and cannot be disabled via `addons`; use
  `addons_to_remove` to turn off a default-installed add-on (runs
  `oci ce cluster disable-addon` through a built-in `terraform_data` local-exec,
  so it needs the OCI CLI on the apply host). The catalog is Kubernetes-version
  specific: `oci ce addon-option list --kubernetes-version <ver> --all`. Unlike
  EKS there is no `before_compute` ordering flag. Anything outside the catalog is
  self-managed via Helm/manifests against the cluster outputs. See the
  **Cluster add-ons** section of the README.
- **Service load balancers are a cluster-level input, not subnet tags.** EKS
  discovers load-balancer subnets from `kubernetes.io/role/elb` tags. OKE takes
  an explicit `service_lb_subnet_id` (required) and hands it to the in-cluster
  `oci-cloud-controller-manager`. See
  [service_load_balancers.md](service_load_balancers.md).
- **Autoscaling is an add-on, not a module input.** EKS node groups carry
  `min_size`/`max_size` that the cluster autoscaler reads from ASG tags. OKE node
  pools have a single `size`; bounds are configured in the `ClusterAutoscaler`
  add-on. Setting `autoscale = true` on a pool switches this module to a
  resource variant that ignores `size` drift so Terraform and the autoscaler do
  not fight.
