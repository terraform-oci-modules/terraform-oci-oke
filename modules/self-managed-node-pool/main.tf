################################################################################
# Self-Managed Node Pool  (maps to self_managed_node_groups)
#
# An instance configuration + instance pool whose nodes self-join the OKE cluster
# via the oke-* launch metadata. Unlike managed node pools, OKE does not manage
# these nodes' lifecycle.
################################################################################

locals {
  is_flex = length(regexall("Flex", var.shape)) > 0

  metadata = merge(
    {
      apiserver_host           = var.apiserver_private_host
      cluster_ca_cert          = var.cluster_ca_cert
      oke-k8version            = var.kubernetes_version
      oke-kubeproxy-proxy-mode = var.kubeproxy_mode
      oke-initial-node-labels  = join(",", [for k, v in var.node_labels : format("%s=%s", k, v)])
      ssh_authorized_keys      = var.ssh_public_key
      user_data                = var.cloud_init
    },
    var.node_metadata,
  )
}

resource "oci_core_instance_configuration" "this" {
  compartment_id = var.compartment_id
  display_name   = var.name
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags

  instance_details {
    instance_type = "compute"

    launch_details {
      compartment_id      = var.compartment_id
      availability_domain = element(var.availability_domains, 0)
      fault_domain        = try(var.placement_fds[0], null)
      shape               = var.shape
      freeform_tags       = var.freeform_tags
      defined_tags        = var.defined_tags
      metadata            = { for k, v in local.metadata : k => v if v != null }

      create_vnic_details {
        subnet_id        = var.subnet_id
        nsg_ids          = var.nsg_ids
        assign_public_ip = var.assign_public_ip
      }

      dynamic "shape_config" {
        for_each = local.is_flex ? [1] : []
        content {
          ocpus         = var.ocpus
          memory_in_gbs = (var.memory / var.ocpus) > 64 ? var.ocpus * 64 : var.memory
        }
      }

      source_details {
        source_type             = "image"
        image_id                = var.image_id
        boot_volume_size_in_gbs = var.boot_volume_size
        kms_key_id              = var.volume_kms_key_id
      }

      is_pv_encryption_in_transit_enabled = var.pv_transit_encryption
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      defined_tags, freeform_tags, display_name,
      instance_details[0].launch_details[0].defined_tags,
      instance_details[0].launch_details[0].freeform_tags,
    ]
  }
}

resource "oci_core_instance_pool" "managed" {
  count = var.autoscale ? 0 : 1

  compartment_id            = var.compartment_id
  display_name              = var.name
  instance_configuration_id = oci_core_instance_configuration.this.id
  size                      = var.size
  freeform_tags             = var.freeform_tags
  defined_tags              = var.defined_tags

  dynamic "placement_configurations" {
    for_each = var.availability_domains
    iterator = ad
    content {
      availability_domain = ad.value
      primary_subnet_id   = var.subnet_id
      fault_domains       = var.placement_fds
    }
  }

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags, display_name, placement_configurations]
  }
}

resource "oci_core_instance_pool" "autoscaled" {
  count = var.autoscale ? 1 : 0

  compartment_id            = var.compartment_id
  display_name              = var.name
  instance_configuration_id = oci_core_instance_configuration.this.id
  size                      = var.size
  freeform_tags             = var.freeform_tags
  defined_tags              = var.defined_tags

  dynamic "placement_configurations" {
    for_each = var.availability_domains
    iterator = ad
    content {
      availability_domain = ad.value
      primary_subnet_id   = var.subnet_id
      fault_domains       = var.placement_fds
    }
  }

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags, display_name, placement_configurations, size]
  }
}
