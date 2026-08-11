provider "oci" {
  region = local.region
}

locals {
  name   = "ex-cluster-addons"
  region = "us-ashburn-1"

  vcn_cidr           = "10.0.0.0/16"
  kubernetes_version = "v1.36.1"

  tags = {
    Example    = local.name
    GithubRepo = "terraform-oci-oke"
    GithubOrg  = "terraform-oci-modules"
  }
}

################################################################################
# VCN (supporting resource)
################################################################################

module "vcn" {
  source  = "terraform-oci-modules/vcn/oci"
  version = "~> 0.7"

  name           = local.name
  compartment_id = var.compartment_id
  vcn_cidr_block = local.vcn_cidr

  public_subnets  = [cidrsubnet(local.vcn_cidr, 4, 0)]
  private_subnets = [cidrsubnet(local.vcn_cidr, 4, 1)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  create_service_gateway = true

  tags = local.tags
}

################################################################################
# OKE cluster (enhanced, required for add-ons) + managed node pool
#
# Add-ons are OKE-managed: OKE installs/upgrades/reconciles them. Add a key to
# turn an optional add-on on; remove it to turn it off. List the catalog for a
# version with:
#   oci ce addon-option list --kubernetes-version v1.36.1 --all --query 'data[*].name'
################################################################################

module "oke" {
  source = "../../"

  name               = local.name
  compartment_id     = var.compartment_id
  kubernetes_version = local.kubernetes_version
  cluster_type       = "enhanced" # required for any add-on
  cni_type           = "flannel"

  vcn_id           = module.vcn.vcn_id
  worker_subnet_id = module.vcn.private_subnets[0]

  # Public control plane endpoint so the cluster is reachable for demos / kubectl,
  # mirroring the terraform-aws-eks examples. Keep this private in production and
  # reach it via a bastion / operator host or VPN, see docs/network_connectivity.md.
  control_plane_subnet_id           = module.vcn.public_subnets[0]
  control_plane_is_public           = true
  assign_public_ip_to_control_plane = true

  service_lb_subnet_id = module.vcn.public_subnets[0]

  ssh_authorized_keys = var.ssh_authorized_keys

  # The registry VCN module's subnets use a lockdown security list (implicit
  # deny). Let the module create the control-plane and worker NSGs and seed them
  # with the recommended OKE ruleset, the path worker nodes need to register
  # with the control plane. See docs/network_connectivity.md.
  create_control_plane_nsg = true
  create_worker_nsg        = true

  addons = {
    # Optional add-on, latest version, default configuration.
    # override_existing: OKE can stage a default install of this addon on new
    # enhanced clusters before Terraform's create call lands, which otherwise
    # races and fails with "expected ACTIVE, got DELETING". true takes over
    # whatever OKE already has in place instead of conflicting with it.
    KubernetesMetricsServer = {
      override_existing = true
    }

    # Optional add-on, latest version.
    CertManager = {
      override_existing = true
    }

    # ClusterAutoscaler is intentionally omitted from this applied example: it
    # calls OCI APIs and so needs IAM (a dynamic group + policy granted outside
    # this module) plus a `nodeGroupAutoDiscovery`/`nodes` configuration, so it
    # cannot be enabled by config alone. Enable it once those are in place:
    #
    #   ClusterAutoscaler = {
    #     version = "v1.34.3"
    #     configurations = [
    #       { key = "nodes", value = "1:5:<node-pool-ocid>" },
    #       { key = "authType", value = "workload" },
    #     ]
    #   }
    #
    # Essential add-ons (CoreDNS, KubeProxy, the CNI) are always installed and
    # managed by OKE, they cannot be (re)added via addons. Use
    # addons_to_remove to turn a default-installed add-on off.
  }

  node_pools = {
    np1 = {
      shape                = "VM.Standard.E4.Flex"
      ocpus                = 2
      memory               = 16
      size                 = 2
      availability_domains = [1]
    }
  }

  tags = local.tags
}
