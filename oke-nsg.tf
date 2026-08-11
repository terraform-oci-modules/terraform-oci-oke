################################################################################
# Network Security Groups  (maps to cluster/node security_group_* in EKS)
#
# Optional, generic NSGs for the control plane and workers. Rules are fully
# user-supplied via *_nsg_ingress_rules / *_nsg_egress_rules so the module stays
# networking-agnostic. Full OKE rulesets are expected from the sibling
# terraform-oci-vcn module or passed in via *_nsg_ids.
################################################################################

locals {
  create_control_plane_nsg = local.create && var.create_control_plane_nsg
  create_worker_nsg        = local.create && var.create_worker_nsg

  # Merged worker NSG list: user-supplied + the worker NSG created here.
  worker_nsg_ids = compact(concat(
    var.worker_nsg_ids,
    var.create_worker_nsg ? [oci_core_network_security_group.worker[0].id] : [],
  ))

  ##############################################################################
  # Recommended OKE rulesets (EKS *_enable_recommended_rules analog)
  #
  # Ports per the OKE network docs: kube-apiserver 6443, kubelet 10250, OKE
  # control-plane 12250, NodePort 30000-32767, ICMP type 3 code 4 for path MTU.
  ##############################################################################
  enable_control_plane_recommended = local.create_control_plane_nsg && var.control_plane_nsg_enable_recommended_rules
  enable_worker_recommended        = local.create_worker_nsg && var.worker_nsg_enable_recommended_rules
  enable_recommended               = local.enable_control_plane_recommended || local.enable_worker_recommended

  # Oracle Services Network destination label (e.g. "all-iad-services-in-oracle-services-network").
  osn_destination = try(data.oci_core_services.recommended[0].services[0].cidr_block, null)

  # Effective NSG ids the recommended rules reference (map *values*; may be
  # unknown at plan when the NSG is created in-module). Prefer the in-module NSG,
  # fall back to the first user-supplied id so cross-references still resolve.
  rec_control_plane_nsg_id = local.create_control_plane_nsg ? oci_core_network_security_group.control_plane[0].id : try(var.control_plane_nsg_ids[0], null)
  rec_worker_nsg_id        = local.create_worker_nsg ? oci_core_network_security_group.worker[0].id : try(var.worker_nsg_ids[0], null)
  rec_pod_nsg_id           = try(var.pod_nsg_ids[0], null)

  # Plan-known gates for which recommended rule *keys* exist. These must not
  # depend on the resolved NSG ids above (unknown at plan for in-module NSGs),
  # otherwise the rule for_each key set is indeterminate.
  have_control_plane_nsg = local.create_control_plane_nsg || length(var.control_plane_nsg_ids) > 0
  have_worker_nsg        = local.create_worker_nsg || length(var.worker_nsg_ids) > 0
  have_pod_nsg           = length(var.pod_nsg_ids) > 0
  rec_npn                = var.cni_type == "npn" && local.have_pod_nsg

  # Uniform rule shape so each recommended map is a single object type (required
  # for for_each). Unused fields stay null.
  rec_rule_base = {
    source   = null, source_type = null, destination = null, destination_type = null
    port_min = null, port_max = null, icmp_type = null, icmp_code = null
  }

  control_plane_recommended_rules = local.enable_control_plane_recommended ? merge(
    {
      "egress-osn" = merge(local.rec_rule_base, {
        direction   = "EGRESS", protocol = "6", description = "Allow TCP egress from control plane to OCI services"
        destination = local.osn_destination, destination_type = "SERVICE_CIDR_BLOCK"
      })
      "ingress-cp-inter" = merge(local.rec_rule_base, {
        direction = "INGRESS", protocol = "6", description = "Allow TCP ingress for control plane inter-communication"
        source    = local.rec_control_plane_nsg_id, source_type = "NETWORK_SECURITY_GROUP", port_min = 6443, port_max = 6443
      })
      "egress-cp-inter" = merge(local.rec_rule_base, {
        direction   = "EGRESS", protocol = "6", description = "Allow TCP egress for control plane inter-communication"
        destination = local.rec_control_plane_nsg_id, destination_type = "NETWORK_SECURITY_GROUP", port_min = 6443, port_max = 6443
      })
    },
    local.have_worker_nsg ? {
      "egress-kubelet" = merge(local.rec_rule_base, {
        direction   = "EGRESS", protocol = "6", description = "Allow TCP egress from control plane to kubelet on workers"
        destination = local.rec_worker_nsg_id, destination_type = "NETWORK_SECURITY_GROUP", port_min = 10250, port_max = 10250
      })
      "ingress-oke" = merge(local.rec_rule_base, {
        direction = "INGRESS", protocol = "6", description = "Allow TCP ingress to OKE control plane from workers"
        source    = local.rec_worker_nsg_id, source_type = "NETWORK_SECURITY_GROUP", port_min = 12250, port_max = 12250
      })
      "egress-oke" = merge(local.rec_rule_base, {
        direction   = "EGRESS", protocol = "6", description = "Allow TCP egress from OKE control plane to workers"
        destination = local.rec_worker_nsg_id, destination_type = "NETWORK_SECURITY_GROUP", port_min = 12250, port_max = 12250
      })
      "ingress-apiserver" = merge(local.rec_rule_base, {
        direction = "INGRESS", protocol = "6", description = "Allow TCP ingress to kube-apiserver from workers"
        source    = local.rec_worker_nsg_id, source_type = "NETWORK_SECURITY_GROUP", port_min = 6443, port_max = 6443
      })
      "egress-icmp" = merge(local.rec_rule_base, {
        direction   = "EGRESS", protocol = "1", description = "Allow ICMP egress for path discovery to workers"
        destination = local.rec_worker_nsg_id, destination_type = "NETWORK_SECURITY_GROUP", icmp_type = 3, icmp_code = 4
      })
      "ingress-icmp" = merge(local.rec_rule_base, {
        direction = "INGRESS", protocol = "1", description = "Allow ICMP ingress for path discovery from workers"
        source    = local.rec_worker_nsg_id, source_type = "NETWORK_SECURITY_GROUP", icmp_type = 3, icmp_code = 4
      })
    } : {},
    local.rec_npn ? {
      "ingress-apiserver-pods" = merge(local.rec_rule_base, {
        direction = "INGRESS", protocol = "6", description = "Allow TCP ingress to kube-apiserver from pods"
        source    = local.rec_pod_nsg_id, source_type = "NETWORK_SECURITY_GROUP", port_min = 6443, port_max = 6443
      })
      "ingress-oke-pods" = merge(local.rec_rule_base, {
        direction = "INGRESS", protocol = "6", description = "Allow TCP ingress to OKE control plane from pods"
        source    = local.rec_pod_nsg_id, source_type = "NETWORK_SECURITY_GROUP", port_min = 12250, port_max = 12250
      })
      "egress-pods" = merge(local.rec_rule_base, {
        direction   = "EGRESS", protocol = "all", description = "Allow all egress from OKE control plane to pods"
        destination = local.rec_pod_nsg_id, destination_type = "NETWORK_SECURITY_GROUP"
      })
    } : {},
    { for cidr in var.control_plane_allowed_cidrs : "ingress-apiserver-${cidr}" => merge(local.rec_rule_base, {
      direction = "INGRESS", protocol = "6", description = "Allow TCP ingress to kube-apiserver from ${cidr}"
      source    = cidr, source_type = "CIDR_BLOCK", port_min = 6443, port_max = 6443
    }) },
  ) : {}

  worker_recommended_rules = local.enable_worker_recommended ? merge(
    {
      "egress-osn" = merge(local.rec_rule_base, {
        direction   = "EGRESS", protocol = "6", description = "Allow TCP egress from workers to OCI services"
        destination = local.osn_destination, destination_type = "SERVICE_CIDR_BLOCK"
      })
      "egress-workers" = merge(local.rec_rule_base, {
        direction   = "EGRESS", protocol = "all", description = "Allow all egress from workers to other workers"
        destination = local.rec_worker_nsg_id, destination_type = "NETWORK_SECURITY_GROUP"
      })
      "ingress-workers" = merge(local.rec_rule_base, {
        direction = "INGRESS", protocol = "all", description = "Allow all ingress to workers from other workers"
        source    = local.rec_worker_nsg_id, source_type = "NETWORK_SECURITY_GROUP"
      })
      "egress-icmp" = merge(local.rec_rule_base, {
        direction   = "EGRESS", protocol = "1", description = "Allow ICMP egress from workers for path discovery"
        destination = "0.0.0.0/0", destination_type = "CIDR_BLOCK", icmp_type = 3, icmp_code = 4
      })
      "ingress-icmp" = merge(local.rec_rule_base, {
        direction = "INGRESS", protocol = "1", description = "Allow ICMP ingress to workers for path discovery"
        source    = "0.0.0.0/0", source_type = "CIDR_BLOCK", icmp_type = 3, icmp_code = 4
      })
    },
    var.worker_allow_internet_egress ? {
      "egress-internet" = merge(local.rec_rule_base, {
        direction   = "EGRESS", protocol = "all", description = "Allow all egress from workers to internet"
        destination = "0.0.0.0/0", destination_type = "CIDR_BLOCK"
      })
    } : {},
    local.have_control_plane_nsg ? {
      "egress-apiserver" = merge(local.rec_rule_base, {
        direction   = "EGRESS", protocol = "6", description = "Allow TCP egress from workers to kube-apiserver"
        destination = local.rec_control_plane_nsg_id, destination_type = "NETWORK_SECURITY_GROUP", port_min = 6443, port_max = 6443
      })
      "egress-oke" = merge(local.rec_rule_base, {
        direction   = "EGRESS", protocol = "6", description = "Allow TCP egress from workers to OKE control plane"
        destination = local.rec_control_plane_nsg_id, destination_type = "NETWORK_SECURITY_GROUP", port_min = 12250, port_max = 12250
      })
      "egress-healthcheck" = merge(local.rec_rule_base, {
        direction   = "EGRESS", protocol = "6", description = "Allow TCP egress from workers to control plane for health check"
        destination = local.rec_control_plane_nsg_id, destination_type = "NETWORK_SECURITY_GROUP", port_min = 10250, port_max = 10250
      })
      "ingress-cp-webhooks" = merge(local.rec_rule_base, {
        direction = "INGRESS", protocol = "all", description = "Allow all ingress to workers from control plane for webhooks"
        source    = local.rec_control_plane_nsg_id, source_type = "NETWORK_SECURITY_GROUP"
      })
    } : {},
    local.rec_npn ? {
      "egress-pods" = merge(local.rec_rule_base, {
        direction   = "EGRESS", protocol = "all", description = "Allow all egress from workers to pods"
        destination = local.rec_pod_nsg_id, destination_type = "NETWORK_SECURITY_GROUP"
      })
      "ingress-pods" = merge(local.rec_rule_base, {
        direction = "INGRESS", protocol = "all", description = "Allow all ingress to workers from pods"
        source    = local.rec_pod_nsg_id, source_type = "NETWORK_SECURITY_GROUP"
      })
    } : {},
  ) : {}
}

# Oracle Services Network lookup for recommended OSN egress rules.
data "oci_core_services" "recommended" {
  count = local.enable_recommended ? 1 : 0

  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_network_security_group" "control_plane" {
  count = local.create_control_plane_nsg ? 1 : 0

  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "${var.name}-control-plane"

  freeform_tags = merge({ "Name" = "${var.name}-control-plane" }, var.tags)
  defined_tags  = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

resource "oci_core_network_security_group" "worker" {
  count = local.create_worker_nsg ? 1 : 0

  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "${var.name}-worker"

  freeform_tags = merge({ "Name" = "${var.name}-worker" }, var.tags)
  defined_tags  = var.defined_tags

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

resource "oci_core_network_security_group_security_rule" "control_plane_ingress" {
  for_each = { for k, v in var.control_plane_nsg_ingress_rules : k => v if local.create_control_plane_nsg }

  network_security_group_id = oci_core_network_security_group.control_plane[0].id
  direction                 = "INGRESS"
  protocol                  = each.value.protocol
  source                    = each.value.source
  source_type               = lookup(each.value, "source_type", "CIDR_BLOCK")
  description               = lookup(each.value, "description", null)

  dynamic "tcp_options" {
    for_each = try(each.value.tcp_options, null) != null ? [each.value.tcp_options] : []
    content {
      destination_port_range {
        min = tcp_options.value.min
        max = tcp_options.value.max
      }
    }
  }

  dynamic "udp_options" {
    for_each = try(each.value.udp_options, null) != null ? [each.value.udp_options] : []
    content {
      destination_port_range {
        min = udp_options.value.min
        max = udp_options.value.max
      }
    }
  }

  dynamic "icmp_options" {
    for_each = try(each.value.icmp_options, null) != null ? [each.value.icmp_options] : []
    content {
      type = icmp_options.value.type
      code = lookup(icmp_options.value, "code", null)
    }
  }
}

resource "oci_core_network_security_group_security_rule" "control_plane_egress" {
  for_each = { for k, v in var.control_plane_nsg_egress_rules : k => v if local.create_control_plane_nsg }

  network_security_group_id = oci_core_network_security_group.control_plane[0].id
  direction                 = "EGRESS"
  protocol                  = each.value.protocol
  destination               = each.value.destination
  destination_type          = lookup(each.value, "destination_type", "CIDR_BLOCK")
  description               = lookup(each.value, "description", null)

  dynamic "tcp_options" {
    for_each = try(each.value.tcp_options, null) != null ? [each.value.tcp_options] : []
    content {
      destination_port_range {
        min = tcp_options.value.min
        max = tcp_options.value.max
      }
    }
  }

  dynamic "udp_options" {
    for_each = try(each.value.udp_options, null) != null ? [each.value.udp_options] : []
    content {
      destination_port_range {
        min = udp_options.value.min
        max = udp_options.value.max
      }
    }
  }

  dynamic "icmp_options" {
    for_each = try(each.value.icmp_options, null) != null ? [each.value.icmp_options] : []
    content {
      type = icmp_options.value.type
      code = lookup(icmp_options.value, "code", null)
    }
  }
}

resource "oci_core_network_security_group_security_rule" "worker_ingress" {
  for_each = { for k, v in var.worker_nsg_ingress_rules : k => v if local.create_worker_nsg }

  network_security_group_id = oci_core_network_security_group.worker[0].id
  direction                 = "INGRESS"
  protocol                  = each.value.protocol
  source                    = each.value.source
  source_type               = lookup(each.value, "source_type", "CIDR_BLOCK")
  description               = lookup(each.value, "description", null)

  dynamic "tcp_options" {
    for_each = try(each.value.tcp_options, null) != null ? [each.value.tcp_options] : []
    content {
      destination_port_range {
        min = tcp_options.value.min
        max = tcp_options.value.max
      }
    }
  }

  dynamic "udp_options" {
    for_each = try(each.value.udp_options, null) != null ? [each.value.udp_options] : []
    content {
      destination_port_range {
        min = udp_options.value.min
        max = udp_options.value.max
      }
    }
  }

  dynamic "icmp_options" {
    for_each = try(each.value.icmp_options, null) != null ? [each.value.icmp_options] : []
    content {
      type = icmp_options.value.type
      code = lookup(icmp_options.value, "code", null)
    }
  }
}

resource "oci_core_network_security_group_security_rule" "worker_egress" {
  for_each = { for k, v in var.worker_nsg_egress_rules : k => v if local.create_worker_nsg }

  network_security_group_id = oci_core_network_security_group.worker[0].id
  direction                 = "EGRESS"
  protocol                  = each.value.protocol
  destination               = each.value.destination
  destination_type          = lookup(each.value, "destination_type", "CIDR_BLOCK")
  description               = lookup(each.value, "description", null)

  dynamic "tcp_options" {
    for_each = try(each.value.tcp_options, null) != null ? [each.value.tcp_options] : []
    content {
      destination_port_range {
        min = tcp_options.value.min
        max = tcp_options.value.max
      }
    }
  }

  dynamic "udp_options" {
    for_each = try(each.value.udp_options, null) != null ? [each.value.udp_options] : []
    content {
      destination_port_range {
        min = udp_options.value.min
        max = udp_options.value.max
      }
    }
  }

  dynamic "icmp_options" {
    for_each = try(each.value.icmp_options, null) != null ? [each.value.icmp_options] : []
    content {
      type = icmp_options.value.type
      code = lookup(icmp_options.value, "code", null)
    }
  }
}

################################################################################
# Recommended ruleset resources (rendered from the locals above)
################################################################################

resource "oci_core_network_security_group_security_rule" "control_plane_recommended" {
  for_each = local.control_plane_recommended_rules

  network_security_group_id = oci_core_network_security_group.control_plane[0].id
  direction                 = each.value.direction
  protocol                  = each.value.protocol
  description               = each.value.description
  source                    = each.value.source
  source_type               = each.value.source_type
  destination               = each.value.destination
  destination_type          = each.value.destination_type

  dynamic "tcp_options" {
    for_each = each.value.protocol == "6" && each.value.port_min != null ? [each.value] : []
    content {
      destination_port_range {
        min = tcp_options.value.port_min
        max = tcp_options.value.port_max
      }
    }
  }

  dynamic "udp_options" {
    for_each = each.value.protocol == "17" && each.value.port_min != null ? [each.value] : []
    content {
      destination_port_range {
        min = udp_options.value.port_min
        max = udp_options.value.port_max
      }
    }
  }

  dynamic "icmp_options" {
    for_each = each.value.icmp_type != null ? [each.value] : []
    content {
      type = icmp_options.value.icmp_type
      code = icmp_options.value.icmp_code
    }
  }
}

resource "oci_core_network_security_group_security_rule" "worker_recommended" {
  for_each = local.worker_recommended_rules

  network_security_group_id = oci_core_network_security_group.worker[0].id
  direction                 = each.value.direction
  protocol                  = each.value.protocol
  description               = each.value.description
  source                    = each.value.source
  source_type               = each.value.source_type
  destination               = each.value.destination
  destination_type          = each.value.destination_type

  dynamic "tcp_options" {
    for_each = each.value.protocol == "6" && each.value.port_min != null ? [each.value] : []
    content {
      destination_port_range {
        min = tcp_options.value.port_min
        max = tcp_options.value.port_max
      }
    }
  }

  dynamic "udp_options" {
    for_each = each.value.protocol == "17" && each.value.port_min != null ? [each.value] : []
    content {
      destination_port_range {
        min = udp_options.value.port_min
        max = udp_options.value.port_max
      }
    }
  }

  dynamic "icmp_options" {
    for_each = each.value.icmp_type != null ? [each.value] : []
    content {
      type = icmp_options.value.icmp_type
      code = icmp_options.value.icmp_code
    }
  }
}
