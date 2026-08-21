module "wrapper" {
  source = "../../modules/virtual-node-pool"

  for_each = var.items

  availability_domains = try(each.value.availability_domains, var.defaults.availability_domains)
  cluster_id           = try(each.value.cluster_id, var.defaults.cluster_id)
  cluster_type         = try(each.value.cluster_type, var.defaults.cluster_type)
  cni_type             = try(each.value.cni_type, var.defaults.cni_type)
  compartment_id       = try(each.value.compartment_id, var.defaults.compartment_id)
  defined_tags         = try(each.value.defined_tags, var.defaults.defined_tags, {})
  fault_domains        = try(each.value.fault_domains, var.defaults.fault_domains, ["FAULT-DOMAIN-1", "FAULT-DOMAIN-2", "FAULT-DOMAIN-3"])
  freeform_tags        = try(each.value.freeform_tags, var.defaults.freeform_tags, {})
  name                 = try(each.value.name, var.defaults.name)
  node_labels          = try(each.value.node_labels, var.defaults.node_labels, {})
  nsg_ids              = try(each.value.nsg_ids, var.defaults.nsg_ids, [])
  pod_nsg_ids          = try(each.value.pod_nsg_ids, var.defaults.pod_nsg_ids, [])
  pod_subnet_id        = try(each.value.pod_subnet_id, var.defaults.pod_subnet_id, null)
  shape                = try(each.value.shape, var.defaults.shape, "Pod.Standard.E4.Flex")
  size                 = try(each.value.size, var.defaults.size, 1)
  subnet_id            = try(each.value.subnet_id, var.defaults.subnet_id)
  taints               = try(each.value.taints, var.defaults.taints, {})
  timeouts             = try(each.value.timeouts, var.defaults.timeouts, {})
}
