module "wrapper" {
  source = "../../modules/self-managed-node-pool"

  for_each = var.items

  apiserver_private_host = try(each.value.apiserver_private_host, var.defaults.apiserver_private_host, null)
  assign_public_ip       = try(each.value.assign_public_ip, var.defaults.assign_public_ip, false)
  autoscale              = try(each.value.autoscale, var.defaults.autoscale, false)
  availability_domains   = try(each.value.availability_domains, var.defaults.availability_domains)
  boot_volume_size       = try(each.value.boot_volume_size, var.defaults.boot_volume_size, 50)
  cloud_init             = try(each.value.cloud_init, var.defaults.cloud_init, null)
  cluster_ca_cert        = try(each.value.cluster_ca_cert, var.defaults.cluster_ca_cert, null)
  compartment_id         = try(each.value.compartment_id, var.defaults.compartment_id)
  defined_tags           = try(each.value.defined_tags, var.defaults.defined_tags, {})
  freeform_tags          = try(each.value.freeform_tags, var.defaults.freeform_tags, {})
  image_id               = try(each.value.image_id, var.defaults.image_id)
  kubeproxy_mode         = try(each.value.kubeproxy_mode, var.defaults.kubeproxy_mode, "iptables")
  kubernetes_version     = try(each.value.kubernetes_version, var.defaults.kubernetes_version)
  memory                 = try(each.value.memory, var.defaults.memory, 16)
  name                   = try(each.value.name, var.defaults.name)
  node_labels            = try(each.value.node_labels, var.defaults.node_labels, {})
  node_metadata          = try(each.value.node_metadata, var.defaults.node_metadata, {})
  nsg_ids                = try(each.value.nsg_ids, var.defaults.nsg_ids, [])
  ocpus                  = try(each.value.ocpus, var.defaults.ocpus, 2)
  placement_fds          = try(each.value.placement_fds, var.defaults.placement_fds, null)
  pv_transit_encryption  = try(each.value.pv_transit_encryption, var.defaults.pv_transit_encryption, true)
  shape                  = try(each.value.shape, var.defaults.shape)
  size                   = try(each.value.size, var.defaults.size, 1)
  ssh_public_key         = try(each.value.ssh_public_key, var.defaults.ssh_public_key, null)
  subnet_id              = try(each.value.subnet_id, var.defaults.subnet_id)
  volume_kms_key_id      = try(each.value.volume_kms_key_id, var.defaults.volume_kms_key_id, null)
}
