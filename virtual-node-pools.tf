################################################################################
# Virtual Node Pools  (maps to fargate_profiles, serverless pods)
################################################################################

locals {
  virtual_node_pools = local.create ? var.virtual_node_pools : {}
}

module "virtual_node_pool" {
  source   = "./modules/virtual-node-pool"
  for_each = local.virtual_node_pools

  depends_on = [oci_containerengine_cluster.this]

  name           = each.key
  cluster_id     = local.cluster_id
  compartment_id = coalesce(each.value.compartment_id, var.compartment_id)
  cluster_type   = var.cluster_type
  cni_type       = var.cni_type

  shape = each.value.shape
  size  = each.value.size

  availability_domains = [
    for ad in coalesce(each.value.availability_domains, [1]) :
    local.availability_domains[ad - 1].name
  ]

  subnet_id     = coalesce(each.value.subnet_id, var.worker_subnet_id)
  pod_subnet_id = coalesce(each.value.pod_subnet_id, var.pod_subnet_id)
  nsg_ids       = length(each.value.nsg_ids) > 0 ? each.value.nsg_ids : local.worker_nsg_ids
  pod_nsg_ids   = length(each.value.pod_nsg_ids) > 0 ? each.value.pod_nsg_ids : var.pod_nsg_ids

  node_labels = each.value.node_labels
  taints      = each.value.taints

  freeform_tags = merge(var.tags, var.worker_tags, each.value.freeform_tags)
  defined_tags  = merge(var.defined_tags, var.worker_defined_tags, each.value.defined_tags)
}
