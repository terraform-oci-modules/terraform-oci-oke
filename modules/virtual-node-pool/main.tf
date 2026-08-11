################################################################################
# OKE Virtual Node Pool  (maps to fargate_profiles, serverless pods)
#
# Requires an ENHANCED cluster with the npn (OCI_VCN_IP_NATIVE) CNI.
################################################################################

resource "oci_containerengine_virtual_node_pool" "this" {
  cluster_id     = var.cluster_id
  compartment_id = var.compartment_id
  display_name   = var.name
  size           = var.size
  nsg_ids        = var.nsg_ids
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags

  dynamic "placement_configurations" {
    for_each = var.availability_domains
    iterator = ad
    content {
      availability_domain = ad.value
      subnet_id           = var.subnet_id
      fault_domain        = var.fault_domains
    }
  }

  pod_configuration {
    shape     = var.shape
    subnet_id = coalesce(var.pod_subnet_id, var.subnet_id)
    nsg_ids   = toset(compact(length(var.pod_nsg_ids) > 0 ? var.pod_nsg_ids : var.nsg_ids))
  }

  dynamic "initial_virtual_node_labels" {
    for_each = var.node_labels
    content {
      key   = initial_virtual_node_labels.key
      value = initial_virtual_node_labels.value
    }
  }

  dynamic "taints" {
    for_each = var.taints
    content {
      key    = taints.key
      value  = taints.value.value
      effect = taints.value.effect
    }
  }

  virtual_node_tags {
    freeform_tags = var.freeform_tags
    defined_tags  = var.defined_tags
  }

  # OKE's virtual node pool deletion cordons/drains pods with a grace period of
  # up to 60m (PT60M) before terminating nodes. Unlike oci_containerengine_node_pool,
  # this resource exposes no eviction settings at all, so the grace period cannot
  # be lowered from Terraform. The provider's default delete timeout is shorter
  # than that ceiling, so a slow-but-otherwise-healthy drain can be aborted by
  # Terraform prematurely.
  timeouts {
    delete = "75m"
  }

  lifecycle {
    ignore_changes = [
      display_name, virtual_node_tags,
      placement_configurations,
      defined_tags, freeform_tags,
    ]

    precondition {
      condition     = var.cluster_type == "enhanced"
      error_message = "Virtual node pools require cluster_type = \"enhanced\" (pool ${var.name})."
    }

    precondition {
      condition     = var.cni_type == "npn"
      error_message = "Virtual node pools require cni_type = \"npn\" (pool ${var.name})."
    }

    precondition {
      condition     = contains(["Pod.Standard.E3.Flex", "Pod.Standard.E4.Flex", "Pod.Standard.A1.Flex"], var.shape)
      error_message = "Virtual node pool shape must be Pod.Standard.E3.Flex, Pod.Standard.E4.Flex, or Pod.Standard.A1.Flex (pool ${var.name})."
    }
  }
}
