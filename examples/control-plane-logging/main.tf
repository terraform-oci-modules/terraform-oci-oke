provider "oci" {
  region = local.region
}

locals {
  name   = "ex-cp-logging"
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

  public_subnets = [cidrsubnet(local.vcn_cidr, 4, 0)]

  create_service_gateway = true

  tags = local.tags
}

################################################################################
# OKE Cluster (basic, no node pools) + control-plane logging
################################################################################

module "oke" {
  source = "../../"

  name               = local.name
  compartment_id     = var.compartment_id
  kubernetes_version = local.kubernetes_version
  cluster_type       = "basic"
  cni_type           = "flannel"

  vcn_id = module.vcn.vcn_id

  # Public control plane endpoint so the cluster is reachable for demos / kubectl,
  # mirroring the terraform-aws-eks examples. Keep this private in production and
  # reach it via a bastion / operator host or VPN, see docs/network_connectivity.md.
  control_plane_subnet_id           = module.vcn.public_subnets[0]
  control_plane_is_public           = true
  assign_public_ip_to_control_plane = true
  control_plane_allowed_cidrs       = ["0.0.0.0/0"]

  service_lb_subnet_id = module.vcn.public_subnets[0]

  create_control_plane_nsg = true

  # Control-plane logging: a dedicated log group plus one log per enabled
  # category, published through OCI Logging. Maps to EKS's enabled_log_types /
  # create_cloudwatch_log_group.
  create_control_plane_log_group       = true
  control_plane_enabled_log_categories = ["kube-apiserver", "kube-scheduler"]
  control_plane_log_retention_duration = 30

  tags = local.tags
}
