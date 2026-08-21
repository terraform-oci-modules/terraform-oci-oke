provider "oci" {
  region = local.region
}

locals {
  name   = "ex-managed-np"
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
  # with the recommended OKE ruleset, the path worker nodes need to register
  # with the control plane. Without this, node pools time out waiting for
  # nodes to join. See docs/network_connectivity.md.
  create_control_plane_nsg = true
  create_worker_nsg        = true

  node_pools = {
    # Fixed-size pool spread across two ADs.
    fixed = {
      shape                = "VM.Standard.E4.Flex"
      ocpus                = 2
      memory               = 16
      size                 = 2
      availability_domains = [1, 2]
      node_labels          = { "pool" = "fixed" }

      # Force both the eviction action and the delete itself once the grace
      # duration elapses, and give this pool a shorter delete timeout than the
      # module's 75m default.
      force_node_action = true
      timeouts = {
        delete = "45m"
      }
    }
    # Autoscaler-managed pool: size is ignored by Terraform after creation.
    autoscaled = {
      shape                = "VM.Standard.E4.Flex"
      ocpus                = 2
      memory               = 16
      size                 = 1
      autoscale            = true
      availability_domains = [1]
      node_labels          = { "pool" = "autoscaled" }
    }
  }

  tags = local.tags
}
