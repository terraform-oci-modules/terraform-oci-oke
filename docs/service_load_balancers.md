# Service load balancers

This document covers how a Kubernetes `Service` of `type: LoadBalancer` gets turned
into a real OCI Load Balancer or Network Load Balancer on a cluster built with this
module, what this module already sets up for you, and what you must verify or create
yourself before it will actually work, **per tenancy/compartment**, since none of this
is guaranteed to already be in place just because another cluster elsewhere in the same
tenancy already has working `LoadBalancer` Services.

## What this module does vs. what OKE does at runtime

Provisioning the actual load balancer is **not something Terraform or this module
does**. It happens entirely at runtime, driven by OKE's built-in
`oci-cloud-controller-manager` (CCM), which runs inside every OKE cluster and watches
for `Service` objects of `type: LoadBalancer`. This module's only role is to give the
CCM its cluster-level defaults:

- `service_lb_subnet_id` (required variable) → becomes the cluster's
  `options.service_lb_config` / default `service_lb_subnet_ids`. The CCM places a
  Service's load balancer here unless the Service overrides it with its own subnet
  annotation (see below).
- `service_lb_backend_nsg_ids` → NSGs applied to load balancer backends.

Everything else (which annotation produces which resource, public vs. private,
subnet overrides, shape/bandwidth, TLS) is pure Kubernetes-side behavior, identical
whether the cluster was built with this module, the official mega-module, or the OCI
Console. There is nothing to configure in this module beyond the two variables above.

## Verified end to end (2026-08-06)

The plain case needs **no extra setup at all**. `examples/simple` was applied against
a real tenancy and an nginx `Deployment` plus a `Service` of `type: LoadBalancer` was
created on it. Result:

- A real OCI classic Load Balancer appeared in the compartment about 40 seconds after
  `kubectl apply`, `ACTIVE`, public, placed in the subnet passed as
  `service_lb_subnet_id`.
- Its backend set contained both worker node private IPs, with backend health `OK`,
  and `curl http://<EXTERNAL-IP>/` returned HTTP 200 from nginx.
- The `flexible` shape and 10/10 Mbps bandwidth came through from the Service's
  annotations.
- The load balancer carried the freeform tags this module passes through
  `options.service_lb_config` (`var.tags` merged with `var.service_lb_tags`),
  confirming that wiring works end to end.

- Deleting the `Service` deleted the load balancer and **reverted** the security list
  rules the CCM had added (see below), leaving the deny-all list empty again.

The important negative result: this tenancy had **zero**
`request.principal.type='cluster'` policy statements anywhere (checked across the
tenancy root and every compartment), and it still worked. See the next section for
what that does and does not mean.

## Prerequisite: IAM grants (needed for some paths, not all)

This module creates **no IAM** (see the README's Required IAM table). Which grants
the CCM actually needs depends on what the Service asks for:

- **A default public classic load balancer with an OCI-assigned ephemeral IP needs
  none of them.** This was verified as described above.
- **Reserved / floating public IPs** (`service.beta.kubernetes.io/oci-load-balancer-*`
  reserved-IP annotations) need the `public-ips` / `floating-ips` grants.
- **Network Load Balancers** (`load-balancer-type: "nlb"`) need the `private-ips` /
  `public-ips` grants.
- **NSG-managed security rules on the load balancer** need the
  `network-security-groups` grant.

```
# Reserved/floating public IP on a classic load balancer
Allow any-user to read public-ips in tenancy where request.principal.type='cluster'
Allow any-user to manage floating-ips in tenancy where request.principal.type='cluster'

# Network Load Balancer (oci.oraclecloud.com/load-balancer-type: "nlb")
Allow any-user to use private-ips in tenancy where all { request.principal.type='cluster', request.principal.compartment.id='<compartment-ocid>' }
Allow any-user to manage public-ips in tenancy where all { request.principal.type='cluster', request.principal.compartment.id='<compartment-ocid>' }

# NSG-based security rules on the load balancer (either type)
Allow any-user to manage network-security-groups in compartment id <compartment-ocid> where request.principal.type='cluster'
```

`request.principal.type='cluster'` is a **built-in** OCI principal type, not a dynamic
group you create. These statements are additive with whatever grants you already made
for `ClusterAutoscaler`, KMS, or worker-node-join. They don't replace them, and they
aren't implied by them. Create them once per compartment/tenancy (home region), the
same way as the module's other Required IAM entries.

If a grant is missing for the path you're using, the Service sits in `Pending`
indefinitely; `kubectl describe service <name>` shows the authorization error as a
`SyncLoadBalancerFailed` event.

## The CCM rewrites your subnet security lists by default

This surprises people, and it is what makes the plain case work even on a locked-down
VCN. The CCM's default
`service.beta.kubernetes.io/oci-load-balancer-security-list-management-mode` is `All`,
meaning it edits the **security lists attached to the load balancer subnet and the
worker subnet** to open the paths it needs. In the verified run above, on a VCN built
by `terraform-oci-vcn` with `lockdown_default_security_list = true` (an empty, deny-all
default security list), the CCM added five rules to that list by itself:

| Direction | Rule                                              | Purpose                       |
| --------- | ------------------------------------------------- | ----------------------------- |
| ingress   | TCP 80 from `0.0.0.0/0`                           | the Service's listener port   |
| ingress   | TCP `<nodePort>` from the LB subnet CIDR          | LB to worker NodePort         |
| ingress   | TCP 10256 from the LB subnet CIDR                 | kube-proxy health check       |
| egress    | TCP `<nodePort>` to the worker subnet CIDR        | LB to worker NodePort         |
| egress    | TCP 10256 to the worker subnet CIDR               | kube-proxy health check       |

Two consequences worth knowing:

- **Your deny-all default security list will not stay deny-all.** If that matters, set
  `security-list-management-mode: "None"` (or `"Frontend"`) on the Service and open the
  paths yourself in the NSGs, or point the load balancer at a subnet whose security
  list you are willing to have edited.
- **It does not show up as Terraform drift.** `terraform-oci-vcn` sets
  `ignore_changes` on the default security list's rules, so `terraform plan` reported
  `No changes` with all five CCM rules in place. Don't read a clean plan as "nothing
  touched my network rules".

## Annotated examples

### Classic public load balancer (default)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  annotations:
    oci.oraclecloud.com/load-balancer-type: "lb"   # optional, this is the default
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
```

Placed in `service_lb_subnet_id` by default. Gets a public IP even if that subnet is
private, unless you also mark it internal (below).

### Network Load Balancer (public)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-nlb
  annotations:
    oci.oraclecloud.com/load-balancer-type: "nlb"
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
```

### Private / internal (either type)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-internal
  annotations:
    oci.oraclecloud.com/load-balancer-type: "lb"
    service.beta.kubernetes.io/oci-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
```

For an internal NLB, use `oci-network-load-balancer.oraclecloud.com/internal: "true"`
instead.

### Overriding the subnet per-Service

Useful when a Service needs a different subnet than the cluster's
`service_lb_subnet_id` default (e.g. a second, more restricted public subnet):

```yaml
metadata:
  annotations:
    oci.oraclecloud.com/load-balancer-type: "lb"
    service.beta.kubernetes.io/oci-load-balancer-subnet1: "ocid1.subnet.oc1..xxxx"
```

For an NLB: `oci-network-load-balancer.oraclecloud.com/subnet: "ocid1.subnet.oc1..xxxx"`.

### Flexible shape / bandwidth (classic LB only)

```yaml
metadata:
  annotations:
    service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
    service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
    service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "100"
```

## Verifying it worked

```bash
kubectl get svc my-app -w        # EXTERNAL-IP moves from <pending> to an address
kubectl describe svc my-app      # events show the CCM's create/attach steps, or the
                                  # authorization error if IAM isn't granted yet
```

The resulting load balancer/NLB is a normal OCI resource in the target compartment,
visible in the Console and manageable like any other, though it's owned by the
Service's lifecycle (delete the Service to delete it).
