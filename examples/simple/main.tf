provider "oci" {
  region = local.region
}

locals {
  name   = "ex-simple"
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

  # Public subnet for the service load balancer; private subnet for workers + control plane.
  public_subnets  = [cidrsubnet(local.vcn_cidr, 4, 0)]
  private_subnets = [cidrsubnet(local.vcn_cidr, 4, 1)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  create_service_gateway = true

  tags = local.tags
}

################################################################################
# OKE Cluster (basic) + one managed node pool
################################################################################

module "oke" {
  source = "../../"

  name               = local.name
  compartment_id     = var.compartment_id
  kubernetes_version = local.kubernetes_version
  cluster_type       = "basic"
  cni_type           = "flannel"

  vcn_id           = module.vcn.vcn_id
  worker_subnet_id = module.vcn.private_subnets[0]

  # Public control plane endpoint so the cluster is reachable for demos / kubectl,
  # mirroring the terraform-aws-eks examples (which set endpoint_public_access = true).
  # For real deployments keep this private and reach it via a bastion / operator host
  # or VPN, see docs/network_connectivity.md.
  control_plane_subnet_id           = module.vcn.public_subnets[0]
  control_plane_is_public           = true
  assign_public_ip_to_control_plane = true

  service_lb_subnet_id = module.vcn.public_subnets[0]

  ssh_authorized_keys = var.ssh_authorized_keys

  # The registry VCN module's subnets use a lockdown security list (implicit
  # deny). Let the module create the control-plane and worker NSGs and seed them
  # with the recommended OKE ruleset (worker <-> control-plane on 6443/10250/12250,
  # node-to-node, ICMP path-MTU, OSN + internet egress). OCI evaluates NSG and
  # security-list rules with OR logic, so these NSGs provide the path OKE needs.
  create_control_plane_nsg = true
  create_worker_nsg        = true

  # Public control-plane endpoint: allow kubectl from anywhere (demo only, keep
  # this tight in production).
  control_plane_allowed_cidrs = ["0.0.0.0/0"]

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
