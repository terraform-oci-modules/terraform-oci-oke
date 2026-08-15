# Upgrades

This covers what actually happens when you bump `kubernetes_version` (or a pool's
`image_id`) and apply: what updates immediately, what does not, and what you have to
opt into explicitly to get a real rolling upgrade. None of this was written down
anywhere in the repo before, and the default behavior (silently leaving running nodes
on the old version) is easy to assume is a bug when it is not.

## Control plane

`kubernetes_version` on `oci_containerengine_cluster` has no `ignore_changes` and is
not `ForceNew`. Bumping it does a normal in-place, OKE-managed control-plane upgrade;
Terraform blocks until it completes (5-13 minutes observed). Nothing to configure.

## Managed node pools: the pool's *template* updates, running nodes do not

**Verified live against a real tenancy (2026-08-15).** Applying a `kubernetes_version`
bump (and the resulting new `image_id`, resolved by `data-images.tf`) updates the
`oci_containerengine_node_pool` resource's `kubernetes_version` and
`node_source_details.image_id` immediately - `terraform plan` shows this as an in-place
update, `0 to add, 0 to destroy`. **It does not touch any already-running node.**
Confirmed with `oci ce node-pool get`: after the apply, the pool's own
`kubernetes-version` field read the new version, but both existing nodes (same names)
still reported the old version and stayed `ACTIVE` throughout.

This is the default, and it is intentional, not a bug: **`node_cycling` defaults to
`enabled = false`.** New nodes (from a future scale-up) pick up the new template; nodes
that already exist keep running the old version/image until you either enable
`node_cycling` or replace them yourself.

### Getting an actual rolling upgrade: `node_cycling`

```hcl
node_pools = {
  np1 = {
    shape = "VM.Standard.E4.Flex"
    # ...
    node_cycling = {
      enabled = true
      # maximum_surge / maximum_unavailable / cycle_modes all have workable
      # defaults (see below) - only set them if you need to tune the rollout.
    }
  }
}
```

Two hard requirements, both enforced by this module with a `terraform plan`-time
`precondition` (not just an OCI API error) as of this doc:

1. **`cluster_type` must be `"enhanced"`.** `node_cycling` is an OCI platform feature
   restricted to enhanced clusters. Enabling it on a `basic` cluster now fails at
   `terraform plan` with `node_cycling requires cluster_type = "enhanced" (pool
   <name>)`, instead of the raw OCI `400 - You have selected a feature restricted to
   Enhanced clusters` error you'd get otherwise.
2. **`maximum_unavailable` must be at least `"1"`** for the default `cycle_modes =
   ["BOOT_VOLUME_REPLACE"]`. This module's own default for `maximum_unavailable` used
   to be `"0"`, which OCI rejects outright (`400 - Non-destructive maxUnavailable at
   least be 1`) - so enabling `node_cycling` with otherwise-default settings failed
   immediately. The default is now `"1"`, so enabling `node_cycling` with no other
   overrides works out of the box.

With both satisfied, `node_cycling` does what you'd expect: OCI actually replaces the
existing nodes. Verified live: `terraform apply` **blocked synchronously for ~9
minutes** while OCI performed the rollout (`maximum_surge = "1"`, `maximum_unavailable
= "1"`, `cycle_modes = ["BOOT_VOLUME_REPLACE"]`), and afterward the same-named nodes
reported the new `kubernetes-version`. Budget apply time accordingly - this is not a
fire-and-forget background operation from Terraform's point of view.

`autoscale = true` pools go through the identical `node_pool_cycling_details` block
(`oci_containerengine_node_pool.autoscaled` in `modules/node-pool/main.tf`), so
everything above applies to them too.

## Self-managed node pools: no rolling-upgrade path exists

`modules/self-managed-node-pool` is a plain `oci_core_instance_configuration` +
`oci_core_instance_pool`, not an OKE-managed resource, so none of the above applies and
OCI gives you materially less here. **This section is a code-and-API-level analysis,
not a live-verified test** (out of scope for the live testing done so far, which only
exercised managed pools via `examples/simple`).

- `oci_core_instance_configuration.this` has `lifecycle { create_before_destroy =
  true }`. Instance configurations are immutable in OCI, so any change to
  `kubernetes_version` (which only flows into the `oke-k8version` cloud-init metadata),
  `image_id`, shape, etc. forces Terraform to create a brand-new instance
  configuration and point the instance pool's `instance_configuration_id` at it.
- `oci_core_instance_pool.managed` / `.autoscaled` treat `instance_configuration_id` as
  a plain in-place-updatable attribute - Terraform's own apply succeeds immediately.
- **But OCI does not retroactively apply the new instance configuration to instances
  that already exist.** Only instances launched after the change (e.g. a future
  scale-up) use it. This matches the AWS ASG launch-template model *without* the ASG
  `instance_refresh` feature EKS's `self_managed_node_groups` uses to roll existing
  instances automatically - there is no OCI or Terraform-provider equivalent here.
- The OCI CLI's `oci compute-management instance-pool reset` looks like the obvious
  candidate for forcing a roll, but it is **not** that: per its own `--help`, `reset`
  "performs the reset (immediate power off and power on)" - a reboot of the existing
  instances on their existing boot volume/image, not a rebuild from the current
  instance configuration. There is no `replace`/`cycle` action in
  `oci compute-management instance-pool --help` at all.
- The only way to actually move existing self-managed nodes onto a new
  `kubernetes_version`/`image_id` today is to **manually terminate instances one at a
  time** (`oci compute instance terminate` or the Console) and let the instance pool's
  own size reconciliation launch a replacement from the *current*
  `instance_configuration_id`. There is no surge/unavailable-budget orchestration like
  `node_cycling` gives managed pools; you own the rollout pacing yourself.

If this needs to be more automated later, it would need to be built into this module
(a `null_resource`/local-exec loop over `list-instances` + `terminate`, or similar) -
nothing upstream provides it.

## Virtual node pools: no version to bump

`oci_containerengine_virtual_node_pool` has no `kubernetes_version` argument at all.
OKE fully owns the virtual node image and Kubernetes version; there is nothing to
configure or roll from this module's side.
