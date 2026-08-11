################################################################################
# Self-Managed Node Pools  (maps to self_managed_node_groups)
################################################################################

locals {
  self_managed_node_pools = local.create ? var.self_managed_node_pools : {}
}

module "self_managed_node_pool" {
  source   = "./modules/self-managed-node-pool"
  for_each = local.self_managed_node_pools

  depends_on = [oci_containerengine_cluster.this]

  name           = each.key
  compartment_id = coalesce(each.value.compartment_id, var.compartment_id)

  kubernetes_version     = coalesce(each.value.kubernetes_version, var.kubernetes_version)
  apiserver_private_host = local.apiserver_private_host
  cluster_ca_cert        = local.cluster_ca_cert
  kubeproxy_mode         = var.kubeproxy_mode
  ssh_public_key         = var.ssh_authorized_keys
  cloud_init             = each.value.cloud_init

  shape            = each.value.shape
  ocpus            = each.value.ocpus
  memory           = each.value.memory
  size             = each.value.size
  autoscale        = each.value.autoscale
  boot_volume_size = each.value.boot_volume_size

  image_id = coalesce(
    each.value.image_id,
    try(local.image_by_sort_key[local.select_image[format("%s/%s/%s",
      trimprefix(lower(coalesce(each.value.kubernetes_version, var.kubernetes_version)), "v"),
      length(regexall("A1|A2", each.value.shape)) > 0 ? "aarch64" : "x86_64",
      length(regexall("GPU", each.value.shape)) > 0 ? "gpu" : "cpu",
    )]], "MISSING_IMAGE"),
  )

  availability_domains = [
    for ad in coalesce(each.value.availability_domains, [1]) :
    local.availability_domains[ad - 1].name
  ]
  placement_fds = each.value.placement_fds

  subnet_id        = coalesce(each.value.subnet_id, var.worker_subnet_id)
  nsg_ids          = length(each.value.nsg_ids) > 0 ? each.value.nsg_ids : local.worker_nsg_ids
  assign_public_ip = each.value.assign_public_ip

  node_labels           = each.value.node_labels
  volume_kms_key_id     = each.value.volume_kms_key_id
  pv_transit_encryption = each.value.pv_transit_encryption
  node_metadata         = merge(var.worker_metadata, each.value.node_metadata)

  freeform_tags = merge(var.tags, var.worker_tags, each.value.freeform_tags)
  defined_tags  = merge(var.defined_tags, var.worker_defined_tags, each.value.defined_tags)
}
