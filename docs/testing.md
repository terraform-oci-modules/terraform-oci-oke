# Testing

The test suite lives in `tests/`: one `.tftest.hcl` file per example, plus `unit_mappings.tftest.hcl` for input→config mapping logic. All tests run from the module root via a single `terraform test` invocation.

## Prerequisites

- Terraform >= 1.6
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

## Known issue: `enhanced` clusters can leave resources stuck on teardown

Verified by running every apply-based test at least once against a real tenancy (2026-08-06).
`simple`, `managed-node-pool`, and `self-managed-node-pool` (all `cluster_type = "basic"`) applied
and destroyed cleanly. `virtual-node-pool`, `cluster-addons`, and `complete` (all
`cluster_type = "enhanced"`) each hit at least one of two OCI-platform-side failures, 100%
correlated with `enhanced` in this testing:

1. **Node/virtual-node-pool deletion hangs or fails.** OCI cordons and drains pods before
   terminating nodes. For **managed** node pools that grace period *is* configurable, and this
   module already sets it to 5 minutes (`PT5M`) through the per-pool `eviction_grace_duration`
   input (OCI's own ceiling is 60 minutes); for **virtual** node pools the provider exposes no
   eviction settings at all. The hangs observed here happened anyway, with the pool ending up in
   `NEEDS_ATTENTION` with an empty error list on both the pool and its nodes and no diagnostic
   detail available, so the configured grace duration is not the cause.

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

2. **`addons` creation can race with OKE's own addon provisioning on new enhanced
   clusters.** Observed repeatedly and consistently with `KubernetesMetricsServer`: Terraform's
   create call fails with `expected ACTIVE, got DELETING`. Setting `override_existing = true` on
   the addon (which allows taking over an addon already installed out-of-band) does **not** fix
   this, that hypothesis was tested and disproven. No workaround has been found yet beyond
   retrying `terraform apply`. Likely the same underlying enhanced-cluster provisioning
   reliability issue as (1), though this has not been confirmed against OCI's internals.

Neither issue reproduces on `basic` clusters. If you hit either while testing, verify and clean up
manually with the OCI CLI (`oci ce cluster list` / `node-pool list` / `virtual-node-pool list` /
`network vcn list`, scoped to your compartment) rather than assuming `terraform test`'s automatic
teardown succeeded.
