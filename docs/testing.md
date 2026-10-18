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

## Node pool teardown

Until this was fixed (2026-10-17), deleting a cluster often failed: a node pool or virtual node
pool delete drained for 60 minutes, then failed with an empty error and left the pool in
`NEEDS_ATTENTION`. Virtual pools failed every time (6 of 6 runs), managed pools sometimes.

The cause was this module, not OCI. The pools referenced the NSGs but not their rules, so on
destroy Terraform deleted all the NSG rules within seconds of starting the pool delete. The nodes
then could not reach the control plane, the drain could never complete, and OKE gave up at the end
of its 60-minute limit. The pools now depend on the NSG rules, so they are deleted first. Verified
live: the virtual pool delete took 2.5 minutes and the `virtual-node-pool` test tore down cleanly.

For a cluster created with an older version, run one `terraform apply` with the new version before
`terraform destroy`, so the state records the new dependencies.

If a pool delete still gets stuck, force it with the OCI CLI, whose delete-time grace-duration
override has no Terraform equivalent:

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
VCN's NSGs, subnets, route tables, gateways, and finally the VCN itself, in that dependency order.
`terraform test` does not retry a failed delete, so after a failure check with the OCI CLI
(`oci ce cluster list`, `node-pool list`, `virtual-node-pool list`, `network vcn list`) instead of
assuming its teardown succeeded.

On managed pools, `force_node_delete = true` makes OKE delete the nodes when the grace period ends
instead of failing.

A virtual pool **create** can also hang: once the provider polled a create work request for about
32 hours while the pool and its nodes had been `ACTIVE` within seconds, then failed with a 404 when
the work request expired and left the pool tainted in state. Setting `timeouts.create` on virtual
pools (for example `"30m"`) bounds that wait.

## Resolved: `KubernetesMetricsServer` failed with `expected ACTIVE, got DELETING`

This was not a race. The add-on's install fails with "Need to install CertManager addon" (visible
in the `ENABLE_ADDON` work request errors) when CertManager is installed at the same time. The
module now creates CertManager first and the other add-ons after it.
