# Network connectivity

This document covers how to reach the OKE cluster control plane (Kubernetes API
server) and how worker/pod traffic is segmented. Like the upstream
[`terraform-aws-eks`](https://github.com/terraform-aws-modules/terraform-aws-eks)
module, **this module does not provision any access infrastructure** (no bastion,
operator host, VPN, or peering). It takes subnet and NSG OCIDs as inputs and leaves
connectivity to you. Build it with the sibling
[`terraform-oci-vcn`](../../terraform-oci-vcn) and
[`terraform-oci-compute-instance`](../../terraform-oci-compute-instance) modules.

## Control plane endpoint access

OKE exposes the API server through a managed endpoint placed in
`control_plane_subnet_id`. Two knobs control reachability:

| Variable | Default | Effect |
| --- | --- | --- |
| `control_plane_is_public` | `false` | Whether the endpoint is reachable from outside the VCN (maps to EKS `endpoint_public_access`). |
| `assign_public_ip_to_control_plane` | `false` | Assigns a public IP to the endpoint (requires `control_plane_is_public` **and** a public `control_plane_subnet_id`). |

This yields three practical configurations, mirroring EKS:

1. **Private only** (default): `control_plane_is_public = false`. The API server is
   reachable only from inside the VCN or a connected network (DRG/LPG/VPN). This is
   the recommended production posture.
2. **Public endpoint**: `control_plane_is_public = true` +
   `assign_public_ip_to_control_plane = true`, with `control_plane_subnet_id` set to a
   **public** subnet. The endpoint gets a public IP; restrict who can reach it with an
   NSG/security-list rule allowing `6443/tcp` only from your office/CI CIDRs. All the
   `examples/` use this so they are runnable out of the box.
3. **Private endpoint + connected network**: private endpoint plus on-prem/peered
   access over DRG, site-to-site VPN, or FastConnect.

> The endpoint subnet always needs an NSG/security-list rule permitting `6443/tcp`
> (and `12250/tcp` for OKE control-plane → worker) from the sources that must reach
> it. When you build the VCN with `terraform-oci-vcn`, add those rules there.

## Reaching a private endpoint

When `control_plane_is_public = false`, `kubectl` must run from somewhere with a route
to the private endpoint. Options, none of which this module creates for you:

- **Operator / bastion host**: a small instance in a subnet that can reach the
  endpoint, provisioned with `terraform-oci-compute-instance`. SSH (or tunnel) in and
  run `kubectl` / `oci ce cluster generate-token` there. This is the closest analog to
  the old mega-module's "operator" host.
- **OCI Bastion service**: a managed SSH bastion with a port-forwarding session to
  `6443` on the endpoint; no standing instance to manage.
- **VPN / FastConnect / DRG**: for on-prem or cross-region access; attach the VCN to a
  DRG and route your network to the endpoint subnet.

The generated `kubeconfig` output uses `oci ce cluster generate-token` as its auth
helper (the OKE analog of `aws eks get-token`), so the OCI CLI must be installed and
configured wherever you run `kubectl`.

> The `addons_to_remove` feature runs `oci ce cluster disable-addon` from the
> **apply host** via the OCI CLI (management plane / control-plane API, not the
> Kubernetes API), so it works regardless of whether the API endpoint is private. It
> does not need cluster network access.

## Worker and pod networking

- **Workers** live in `worker_subnet_id`, normally a **private** subnet with outbound
  access via a NAT gateway and OCI service access via a service gateway.
- **Pods** depend on the CNI:
  - `cni_type = "flannel"` (overlay): pods share the worker subnet; no pod subnet
    needed.
  - `cni_type = "npn"` (OCI VCN-native): pods get VCN IPs from a dedicated
    `pod_subnet_id`. Required for virtual node pools.
- **Service load balancers** are created by OKE in `service_lb_subnet_id`, public for
  internet-facing services, private for internal ones. This is entirely handled at
  runtime by OKE's `oci-cloud-controller-manager`, not by this module, see
  [docs/service_load_balancers.md](service_load_balancers.md) for the annotations that
  control it and the IAM grants it needs (not created by this module, and not something
  to assume already exists in a given tenancy/compartment just because another cluster
  there already has it working).

## Security groups (NSGs)

This module does not own the full OKE NSG rulesets. Build them with
`terraform-oci-vcn` and pass the OCIDs in (`control_plane_nsg_ids`, per-pool
`nsg_ids` / `pod_nsg_ids`).

For convenience it can optionally create one control-plane NSG and one worker NSG
(`create_control_plane_nsg` / `create_worker_nsg`, both default `false`). When created,
each is seeded with a **recommended OKE ruleset**, the OKE analog of EKS
`node_security_group_enable_recommended_rules`: control-plane to worker to pod
communication on `6443` (kube-apiserver), `10250` (kubelet) and `12250` (OKE),
ICMP type 3 code 4 path-MTU discovery, egress to the Oracle Services Network, and
(by default) worker egress to the internet. Toggle with
`control_plane_nsg_enable_recommended_rules` / `worker_nsg_enable_recommended_rules`
(both default `true`), restrict API server reachability with
`control_plane_allowed_cidrs`, drop the blanket egress rule with
`worker_allow_internet_egress = false`, and add extras through
`*_nsg_ingress_rules` / `*_nsg_egress_rules`.

That ruleset is enough to bring a cluster up (every `examples/` directory relies
on it, because `terraform-oci-vcn` defaults `lockdown_default_security_list = true`),
but it is a single flat NSG per tier. It is not a substitute for the full tiered
OKE ruleset that the VCN module models. See
[feature_parity.md](feature_parity.md#network-security-groups) for the mapping
against the EKS security-group variables.
