# Testing

The test suite lives in `tests/`: one `.tftest.hcl` file per example, plus `unit_mappings.tftest.hcl` for input→config mapping logic. All tests run from the module root via a single `terraform test` invocation.

## Prerequisites

- Terraform >= 1.7
- OCI credentials configured, any of:
  - Environment variables (`OCI_CLI_TENANCY`, `OCI_CLI_USER`, `OCI_CLI_FINGERPRINT`, `OCI_CLI_KEY_FILE`, `OCI_CLI_REGION`)
  - A config file at `~/.oci/config`
  - Instance principal (when running from an OCI compute instance)
- A target compartment OCID

## Quick start (free, no credentials needed)

`tests/unit_mappings.tftest.hcl` uses `command = plan` against a `mock_provider`, so it needs no OCI
credentials and creates nothing. It exercises the input→config mappings (cluster type, CNI type,
IPv6, recommended NSG ruleset generation) and is the fastest way to sanity-check a change:

```bash
terraform init
terraform test -filter=tests/unit_mappings.tftest.hcl
```

## Running the apply-based example tests

```bash
export TF_VAR_compartment_id="ocid1.compartment.oc1.."
terraform init
terraform test -filter=tests/simple.tftest.hcl
```

## Running all tests

```bash
export TF_VAR_compartment_id="ocid1.compartment.oc1.."
terraform init
terraform test
```

## Notes

- Every test file other than `unit_mappings.tftest.hcl` uses `command = apply`: they create and
  destroy **real** OCI resources (cluster, node pools) and will incur cost and take significantly
  longer than a plan.
- `cluster-addons.tftest.hcl`, `managed-node-pool.tftest.hcl`, `self-managed-node-pool.tftest.hcl`
  and `virtual-node-pool.tftest.hcl` each stand up a full cluster plus the relevant pool type; they
  are the most expensive/slowest tests in the suite.
- Every example (and therefore every apply-based test) provisions its own VCN via the published
  `terraform-oci-modules/vcn/oci` registry module (not the local sibling checkout), alongside the
  cluster itself.
- No test exercises the Kubernetes API of the cluster it builds; the assertions are all on
  Terraform outputs. Anything that only manifests in-cluster (workloads scheduling, `Service` of
  `type: LoadBalancer` provisioning a real OCI load balancer) has to be checked by hand, see below.

## Manual check: workloads and Service load balancers

`terraform test` proves the cluster resource exists, not that it runs anything. To confirm the
data plane end to end, apply `examples/simple` and drive it with `kubectl`:

```bash
cd examples/simple
terraform apply -var "compartment_id=$COMPARTMENT_ID"

oci ce cluster create-kubeconfig \
  --cluster-id "$(terraform output -raw cluster_id)" \
  --file ./kubeconfig --region <region> --token-version 2.0.0 \
  --kube-endpoint PUBLIC_ENDPOINT
export KUBECONFIG=$PWD/kubeconfig

kubectl get nodes                       # workers joined and Ready
kubectl create deployment nginx --image=nginx:1.27-alpine
kubectl expose deployment nginx --type=LoadBalancer --port=80
kubectl get svc nginx -w                # EXTERNAL-IP goes from <pending> to an address
curl "http://$(kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/"

oci lb load-balancer list -c "$COMPARTMENT_ID"   # the real OCI LB the CCM created
```

This was run on 2026-08-06 and passed: both workers `Ready`, a public classic OCI Load Balancer
`ACTIVE` in `service_lb_subnet_id` within about 40 seconds, both node IPs in the backend set with
health `OK`, and HTTP 200 from nginx through the load balancer. Deleting the `Service` deleted the
load balancer. Full write-up, including what the cloud-controller-manager does to your subnet
security lists, in [service_load_balancers.md](service_load_balancers.md).

> Delete the `Service` before `terraform destroy`. The load balancer belongs to the Service, not to
> Terraform, so leaving it behind blocks subnet deletion and orphans a billable resource.

## Known issue: node pool teardown can hang or fail on any cluster type

> `node_cycling` (rolling node upgrades on managed pools) is a separate `enhanced`-only
> requirement, unrelated to the teardown issue below. See
> [docs/upgrades.md](upgrades.md).

Verified by running every apply-based test at least once against a real tenancy (2026-08-06).
`simple`, `managed-node-pool`, and `self-managed-node-pool` (all `cluster_type = "basic"`) applied
and destroyed cleanly that round. `virtual-node-pool`, `cluster-addons`, and `complete` (all
`cluster_type = "enhanced"`) each hit at least one of two OCI-platform-side failures that same
round, which at the time looked 100% correlated with `enhanced`.

**Update (2026-08-21):** that correlation does not hold. Two consecutive live runs of
`managed-node-pool` (`cluster_type = "basic"`) each hit the node-pool-stuck-in-`NEEDS_ATTENTION`
failure below - a different pool each time (`autoscaled` the first run, `fixed` the second), both
otherwise-default configuration. This is intermittent OCI-platform-side flakiness that can affect
managed node pools on any cluster type, not just `enhanced`. The manual force-delete runbook below
is the fix regardless of `cluster_type`.

1. **Node/virtual-node-pool deletion hangs or fails.** OCI cordons and drains pods before
   terminating nodes. For **managed** node pools that grace period *is* configurable, and this
   module already sets it to 5 minutes (`PT5M`) through the per-pool `eviction_grace_duration`
   input (OCI's own ceiling is 60 minutes); for **virtual** node pools the provider exposes no
   eviction settings at all. The hangs observed in the original 2026-08-06 testing happened anyway,
   with the pool ending up in `NEEDS_ATTENTION` with an empty error list on both the pool and its
   nodes and no diagnostic detail available, so the configured grace duration was not the cause.
   The 2026-08-21 recurrence (see above) surfaced an actual work-request error message this time -
   `"1 nodes(s) pod eviction timeout"` - rather than an empty error list, so this may be the same
   underlying issue with more diagnostic detail available, or a related-but-distinct failure mode.
   Either way the fix is the same manual force-delete below.

   **Update (2026-10-15):** reproduced four times on provider 9.9.0 with a virtual pool that
   ran no workloads. The virtual pool delete sits on "Terminating all instances from virtual
   node pool" with the virtual nodes `ACTIVE`, then fails after exactly 61 minutes (the 60
   minute grace period plus overhead) with an empty work-request error and the pool in
   `NEEDS_ATTENTION`. Teardown order does not matter: it failed the same way when the virtual
   pool was deleted first, with the managed nodes still up to take evicted pods. OKE does not
   force-terminate at the end of the grace period for virtual pools, and the provider has no
   argument to make it, so plan on the force-delete below (it finishes in about 3 minutes).

   The same run showed it for a managed pool too. With the virtual pool gone, the last managed
   pool (one node, `eviction_grace_duration = 3600`, `force_node_delete = false`) sat draining
   for the full hour and failed with `"1 nodes(s) pod eviction timeout"` into
   `NEEDS_ATTENTION`. Terminating the node's compute instance mid-drain did not help: OKE kept
   waiting on the drain. The force-delete below then took 33 seconds. On managed pools,
   `force_node_delete = true` makes OKE delete the nodes when the grace period ends instead of
   failing.

   A virtual pool **create** can also hang: once the provider polled a create work request for
   about 32 hours while the pool and its nodes had been `ACTIVE` within seconds, then failed
   with a 404 when the work request expired and left the pool tainted in state. Setting
   `timeouts.create` on virtual pools (for example `"30m"`) bounds that wait.

   `terraform test`'s own teardown does not retry this and leaves the cluster, node pool/virtual
   node pool, NSGs, and full VCN (subnets, gateways, route tables) in the compartment. This module
   sets `timeouts { delete = "75m" }` on the node pool and virtual node pool resources so Terraform
   doesn't abort a slow-but-otherwise-healthy drain early, but that does **not** fix a genuinely
   stuck deletion, only a premature-timeout one. When it happens, force it via the OCI CLI, whose
   delete-time grace-duration override has no Terraform equivalent:

   ```bash
   # Regular node pool
   oci ce node-pool delete --node-pool-id <ocid> \
     --override-eviction-grace-duration PT0M \
     --is-force-deletion-after-override-grace-duration true --force

   # Virtual node pool
   oci ce virtual-node-pool delete --virtual-node-pool-id <ocid> \
     --override-eviction-grace-duration-vnp PT0M \
     --is-force-deletion-after-override-grace-duration-vnp true --force
   ```

   Then delete the cluster (`oci ce cluster delete --cluster-id <ocid> --force`), followed by the
   VCN's NSGs, subnets, route tables, gateways, and finally the VCN itself, in that dependency
   order.

2. **Resolved: `KubernetesMetricsServer` failed with `expected ACTIVE, got DELETING`.** This
   was not a race. The add-on's install fails with "Need to install CertManager addon" (visible in
   the `ENABLE_ADDON` work request errors) when CertManager is installed at the same time. The
   module now creates CertManager first and the other add-ons after it.

If you hit (1) while testing, verify and clean up
manually with the OCI CLI (`oci ce cluster list` / `node-pool list` / `virtual-node-pool list` /
`network vcn list`, scoped to your compartment) rather than assuming `terraform test`'s automatic
teardown succeeded.
