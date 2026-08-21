################################################################################
# OKE Managed Node Pool  (maps to eks_managed_node_groups)
#
# Two resources implement the same node pool: "autoscaled" ignores size changes
# (size is owned by cluster-autoscaler), "managed" reconciles size from config.
# Exactly one is created per call, selected by var.autoscale.
################################################################################

locals {
  is_flex        = length(regexall("Flex", var.shape)) > 0
  is_npn         = var.cni_type == "npn"
  memory_clamped = (var.memory / var.ocpus) > 64 ? var.ocpus * 64 : var.memory

  node_metadata = merge(
    {
      apiserver_host           = var.apiserver_private_host
      oke-kubeproxy-proxy-mode = var.kubeproxy_mode
    },
    var.node_metadata,
  )
}

resource "oci_containerengine_node_pool" "managed" {
  count = var.autoscale ? 0 : 1

  cluster_id          = var.cluster_id
  compartment_id      = var.compartment_id
  kubernetes_version  = var.kubernetes_version
  name                = var.name
  node_shape          = var.shape
  network_launch_type = var.network_launch_type
  ssh_public_key      = var.ssh_public_key
  freeform_tags       = var.freeform_tags
  defined_tags        = var.defined_tags
  node_metadata       = local.node_metadata

  node_config_details {
    size                                = var.size
    nsg_ids                             = var.nsg_ids
    kms_key_id                          = var.volume_kms_key_id
    is_pv_encryption_in_transit_enabled = var.pv_transit_encryption
    freeform_tags                       = var.freeform_tags
    defined_tags                        = var.defined_tags

    dynamic "placement_configs" {
      for_each = var.availability_domains
      iterator = ad
      content {
        availability_domain     = ad.value
        subnet_id               = var.subnet_id
        capacity_reservation_id = var.capacity_reservation_id
        fault_domains           = var.placement_fds

        dynamic "preemptible_node_config" {
          for_each = var.preemptible_config.enable ? [1] : []
          content {
            preemption_action {
              type                    = "TERMINATE"
              is_preserve_boot_volume = var.preemptible_config.is_preserve_boot_volume
            }
          }
        }
      }
    }

    dynamic "node_pool_pod_network_option_details" {
      for_each = local.is_npn ? [1] : []
      content {
        cni_type          = "OCI_VCN_IP_NATIVE"
        max_pods_per_node = var.max_pods_per_node
        pod_nsg_ids       = compact(var.pod_nsg_ids)
        pod_subnet_ids    = compact([var.pod_subnet_id])
      }
    }

    dynamic "node_pool_pod_network_option_details" {
      for_each = local.is_npn ? [] : [1]
      content {
        cni_type = "FLANNEL_OVERLAY"
      }
    }
  }

  dynamic "node_shape_config" {
    for_each = local.is_flex ? [1] : []
    content {
      ocpus         = var.ocpus
      memory_in_gbs = local.memory_clamped
    }
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = var.image_id
    boot_volume_size_in_gbs = var.boot_volume_size
  }

  node_eviction_node_pool_settings {
    eviction_grace_duration              = var.eviction_grace_duration % 60 == 0 ? format("PT%dM", var.eviction_grace_duration / 60) : format("PT%dS", var.eviction_grace_duration)
    is_force_delete_after_grace_duration = var.force_node_delete
    is_force_action_after_grace_duration = var.force_node_action
  }

  dynamic "node_pool_cycling_details" {
    for_each = var.node_cycling.enabled ? [1] : []
    content {
      is_node_cycling_enabled = true
      maximum_surge           = var.node_cycling.maximum_surge
      maximum_unavailable     = var.node_cycling.maximum_unavailable
      cycle_modes             = var.node_cycling.cycle_modes
    }
  }

  dynamic "initial_node_labels" {
    for_each = var.node_labels
    content {
      key   = initial_node_labels.key
      value = initial_node_labels.value
    }
  }

  dynamic "secondary_vnics" {
    for_each = var.secondary_vnics
    content {
      display_name = secondary_vnics.value.display_name
      nic_index    = secondary_vnics.value.nic_index

      create_vnic_details {
        subnet_id              = secondary_vnics.value.subnet_id
        assign_public_ip       = secondary_vnics.value.assign_public_ip
        assign_ipv6ip          = secondary_vnics.value.assign_ipv6ip
        nsg_ids                = secondary_vnics.value.nsg_ids
        skip_source_dest_check = secondary_vnics.value.skip_source_dest_check
        ip_count               = secondary_vnics.value.ip_count
        display_name           = secondary_vnics.value.display_name

        freeform_tags = merge(var.freeform_tags, secondary_vnics.value.freeform_tags)
        defined_tags  = merge(var.defined_tags, secondary_vnics.value.defined_tags)
      }
    }
  }

  # OKE's node pool deletion cordons/drains pods before terminating nodes. The
  # grace period is set above via node_eviction_node_pool_settings, but OCI's
  # ceiling is 60m (PT60M) and drains have been observed to overrun regardless.
  # The provider's default delete timeout is shorter than that ceiling, so a
  # slow-but-otherwise-healthy drain can be aborted by Terraform prematurely.
  # var.timeouts.delete defaults to "75m", preserving that behavior.
  timeouts {
    create = var.timeouts.create
    update = var.timeouts.update
    delete = var.timeouts.delete
  }

  lifecycle {
    ignore_changes = [
      defined_tags, freeform_tags,
      node_config_details[0].placement_configs,
    ]

    precondition {
      condition     = var.capacity_reservation_id == null || length(var.availability_domains) == 1
      error_message = "A single availability domain must be specified when using a capacity reservation (pool ${var.name})."
    }

    precondition {
      condition     = !local.is_npn || var.pod_subnet_id != null
      error_message = "pod_subnet_id is required for npn (OCI_VCN_IP_NATIVE) node pools (pool ${var.name})."
    }

    precondition {
      condition     = !var.node_cycling.enabled || lower(var.cluster_type) == "enhanced"
      error_message = "node_cycling requires cluster_type = \"enhanced\" (pool ${var.name})."
    }
  }
}

resource "oci_containerengine_node_pool" "autoscaled" {
  count = var.autoscale ? 1 : 0

  cluster_id          = var.cluster_id
  compartment_id      = var.compartment_id
  kubernetes_version  = var.kubernetes_version
  name                = var.name
  node_shape          = var.shape
  network_launch_type = var.network_launch_type
  ssh_public_key      = var.ssh_public_key
  freeform_tags       = var.freeform_tags
  defined_tags        = var.defined_tags
  node_metadata       = local.node_metadata

  node_config_details {
    size                                = var.size
    nsg_ids                             = var.nsg_ids
    kms_key_id                          = var.volume_kms_key_id
    is_pv_encryption_in_transit_enabled = var.pv_transit_encryption
    freeform_tags                       = var.freeform_tags
    defined_tags                        = var.defined_tags

    dynamic "placement_configs" {
      for_each = var.availability_domains
      iterator = ad
      content {
        availability_domain     = ad.value
        subnet_id               = var.subnet_id
        capacity_reservation_id = var.capacity_reservation_id
        fault_domains           = var.placement_fds

        dynamic "preemptible_node_config" {
          for_each = var.preemptible_config.enable ? [1] : []
          content {
            preemption_action {
              type                    = "TERMINATE"
              is_preserve_boot_volume = var.preemptible_config.is_preserve_boot_volume
            }
          }
        }
      }
    }

    dynamic "node_pool_pod_network_option_details" {
      for_each = local.is_npn ? [1] : []
      content {
        cni_type          = "OCI_VCN_IP_NATIVE"
        max_pods_per_node = var.max_pods_per_node
        pod_nsg_ids       = compact(var.pod_nsg_ids)
        pod_subnet_ids    = compact([var.pod_subnet_id])
      }
    }

    dynamic "node_pool_pod_network_option_details" {
      for_each = local.is_npn ? [] : [1]
      content {
        cni_type = "FLANNEL_OVERLAY"
      }
    }
  }

  dynamic "node_shape_config" {
    for_each = local.is_flex ? [1] : []
    content {
      ocpus         = var.ocpus
      memory_in_gbs = local.memory_clamped
    }
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = var.image_id
    boot_volume_size_in_gbs = var.boot_volume_size
  }

  node_eviction_node_pool_settings {
    eviction_grace_duration              = var.eviction_grace_duration % 60 == 0 ? format("PT%dM", var.eviction_grace_duration / 60) : format("PT%dS", var.eviction_grace_duration)
    is_force_delete_after_grace_duration = var.force_node_delete
    is_force_action_after_grace_duration = var.force_node_action
  }

  dynamic "node_pool_cycling_details" {
    for_each = var.node_cycling.enabled ? [1] : []
    content {
      is_node_cycling_enabled = true
      maximum_surge           = var.node_cycling.maximum_surge
      maximum_unavailable     = var.node_cycling.maximum_unavailable
      cycle_modes             = var.node_cycling.cycle_modes
    }
  }

  dynamic "initial_node_labels" {
    for_each = var.node_labels
    content {
      key   = initial_node_labels.key
      value = initial_node_labels.value
    }
  }

  dynamic "secondary_vnics" {
    for_each = var.secondary_vnics
    content {
      display_name = secondary_vnics.value.display_name
      nic_index    = secondary_vnics.value.nic_index

      create_vnic_details {
        subnet_id              = secondary_vnics.value.subnet_id
        assign_public_ip       = secondary_vnics.value.assign_public_ip
        assign_ipv6ip          = secondary_vnics.value.assign_ipv6ip
        nsg_ids                = secondary_vnics.value.nsg_ids
        skip_source_dest_check = secondary_vnics.value.skip_source_dest_check
        ip_count               = secondary_vnics.value.ip_count
        display_name           = secondary_vnics.value.display_name

        freeform_tags = merge(var.freeform_tags, secondary_vnics.value.freeform_tags)
        defined_tags  = merge(var.defined_tags, secondary_vnics.value.defined_tags)
      }
    }
  }

  # OKE's node pool deletion cordons/drains pods before terminating nodes. The
  # grace period is set above via node_eviction_node_pool_settings, but OCI's
  # ceiling is 60m (PT60M) and drains have been observed to overrun regardless.
  # The provider's default delete timeout is shorter than that ceiling, so a
  # slow-but-otherwise-healthy drain can be aborted by Terraform prematurely.
  # var.timeouts.delete defaults to "75m", preserving that behavior.
  timeouts {
    create = var.timeouts.create
    update = var.timeouts.update
    delete = var.timeouts.delete
  }

  lifecycle {
    ignore_changes = [
      defined_tags, freeform_tags,
      node_config_details[0].placement_configs,
      node_config_details[0].size,
    ]

    precondition {
      condition     = var.capacity_reservation_id == null || length(var.availability_domains) == 1
      error_message = "A single availability domain must be specified when using a capacity reservation (pool ${var.name})."
    }

    precondition {
      condition     = !local.is_npn || var.pod_subnet_id != null
      error_message = "pod_subnet_id is required for npn (OCI_VCN_IP_NATIVE) node pools (pool ${var.name})."
    }

    precondition {
      condition     = !var.node_cycling.enabled || lower(var.cluster_type) == "enhanced"
      error_message = "node_cycling requires cluster_type = \"enhanced\" (pool ${var.name})."
    }
  }
}
