################################################################################
# Managed Node Pools  (maps to eks_managed_node_groups)
################################################################################

locals {
  node_pools = local.create ? var.node_pools : {}
}

module "node_pool" {
  source   = "./modules/node-pool"
  for_each = local.node_pools

  depends_on = [oci_containerengine_cluster.this]

  name           = each.key
  cluster_id     = local.cluster_id
  compartment_id = coalesce(each.value.compartment_id, var.compartment_id)
  cni_type       = var.cni_type
  ssh_public_key = var.ssh_authorized_keys
  kubeproxy_mode = var.kubeproxy_mode

  apiserver_private_host = local.apiserver_private_host
  node_metadata          = merge(var.worker_metadata, each.value.node_metadata)

  kubernetes_version = coalesce(each.value.kubernetes_version, var.kubernetes_version)
  shape              = each.value.shape
  ocpus              = each.value.ocpus
  memory             = each.value.memory
  size               = each.value.size
  autoscale          = each.value.autoscale
  boot_volume_size   = each.value.boot_volume_size

  # Resolve image: explicit image_id wins, else newest OKE image for version/arch.
  image_id = coalesce(
    each.value.image_id,
    try(local.image_by_sort_key[local.select_image[format("%s/%s/%s",
      trimprefix(lower(coalesce(each.value.kubernetes_version, var.kubernetes_version)), "v"),
      length(regexall("A1|A2", each.value.shape)) > 0 ? "aarch64" : "x86_64",
      length(regexall("GPU", each.value.shape)) > 0 ? "gpu" : "cpu",
    )]], "MISSING_IMAGE"),
  )

  # Resolve AD numbers (1/2/3) → tenancy AD names.
  availability_domains = [
    for ad in coalesce(each.value.availability_domains, [1]) :
    local.availability_domains[ad - 1].name
  ]
  placement_fds = each.value.placement_fds

  subnet_id         = coalesce(each.value.subnet_id, var.worker_subnet_id)
  nsg_ids           = length(each.value.nsg_ids) > 0 ? each.value.nsg_ids : local.worker_nsg_ids
  pod_subnet_id     = try(coalesce(each.value.pod_subnet_id, var.pod_subnet_id), null)
  pod_nsg_ids       = length(each.value.pod_nsg_ids) > 0 ? each.value.pod_nsg_ids : var.pod_nsg_ids
  max_pods_per_node = each.value.max_pods_per_node

  node_labels             = each.value.node_labels
  volume_kms_key_id       = each.value.volume_kms_key_id
  pv_transit_encryption   = each.value.pv_transit_encryption
  capacity_reservation_id = each.value.capacity_reservation_id
  preemptible_config      = each.value.preemptible_config
  eviction_grace_duration = each.value.eviction_grace_duration
  force_node_delete       = each.value.force_node_delete
  node_cycling            = each.value.node_cycling

  freeform_tags = merge(var.tags, var.worker_tags, each.value.freeform_tags)
  defined_tags  = merge(var.defined_tags, var.worker_defined_tags, each.value.defined_tags)
}
