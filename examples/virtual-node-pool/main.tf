provider "oci" {
  region = local.region
}

locals {
  name   = "ex-virtual-np"
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

  public_subnets = [cidrsubnet(local.vcn_cidr, 4, 0)]
  private_subnets = [
    cidrsubnet(local.vcn_cidr, 4, 1), # workers
    cidrsubnet(local.vcn_cidr, 2, 1), # pods
  ]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  create_service_gateway = true

  tags = local.tags
}

# Virtual node pools require an enhanced cluster with the npn (VCN-native) CNI.
module "oke" {
  source = "../../"

  name               = local.name
  compartment_id     = var.compartment_id
  kubernetes_version = local.kubernetes_version
  cluster_type       = "enhanced"
  cni_type           = "npn"

  vcn_id           = module.vcn.vcn_id
  worker_subnet_id = module.vcn.private_subnets[0]
  pod_subnet_id    = module.vcn.private_subnets[1]

  # Public control plane endpoint so the cluster is reachable for demos / kubectl,
  # mirroring the terraform-aws-eks examples. Keep this private in production and
  # reach it via a bastion / operator host or VPN, see docs/network_connectivity.md.
  control_plane_subnet_id           = module.vcn.public_subnets[0]
  control_plane_is_public           = true
  assign_public_ip_to_control_plane = true

  service_lb_subnet_id = module.vcn.public_subnets[0]

  # The registry VCN module's subnets use a lockdown security list (implicit
  # deny). Let the module create the control-plane and worker NSGs and seed them
  # with the recommended OKE ruleset, the path virtual nodes need to register
  # with the control plane. See docs/network_connectivity.md.
  create_control_plane_nsg = true
  create_worker_nsg        = true

  virtual_node_pools = {
    vnp1 = {
      shape                = "Pod.Standard.E4.Flex"
      size                 = 2
      availability_domains = [1, 2]
      node_labels          = { "pool" = "virtual" }
      taints = {
        dedicated = { value = "virtual", effect = "NoSchedule" }
      }
    }
  }

  tags = local.tags
}
