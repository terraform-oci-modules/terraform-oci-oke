provider "oci" {
  region = local.region
}

locals {
  name   = "ex-self-managed-np"
  region = "us-ashburn-1"

  vcn_cidr           = "10.0.0.0/16"
  kubernetes_version = "v1.36.1"

  tags = {
    Example    = local.name
    GithubRepo = "terraform-oci-oke"
    GithubOrg  = "terraform-oci-modules"
  }
}

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

# Self-managed nodes are an instance pool whose nodes self-join the cluster via
# launch metadata. OKE does not manage their lifecycle.
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
  # mirroring the terraform-aws-eks examples. Keep this private in production and
  # reach it via a bastion / operator host or VPN, see docs/network_connectivity.md.
  control_plane_subnet_id           = module.vcn.public_subnets[0]
  control_plane_is_public           = true
  assign_public_ip_to_control_plane = true

  service_lb_subnet_id = module.vcn.public_subnets[0]

  ssh_authorized_keys = var.ssh_authorized_keys

  # The registry VCN module's subnets use a lockdown security list (implicit
  # deny). Let the module create the control-plane and worker NSGs and seed them
  # with the recommended OKE ruleset, the path self-managed nodes need to join
  # the control plane. Without this, instances launch but never reach Active
  # in the node pool. See docs/network_connectivity.md.
  create_control_plane_nsg = true
  create_worker_nsg        = true

  self_managed_node_pools = {
    smp1 = {
      shape                = "VM.Standard.E4.Flex"
      ocpus                = 2
      memory               = 16
      size                 = 2
      availability_domains = [1]
      node_labels          = { "pool" = "self-managed" }
    }
  }

  tags = local.tags
}
