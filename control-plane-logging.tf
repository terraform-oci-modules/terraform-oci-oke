################################################################################
# Control-plane logging  (maps to EKS enabled_log_types / create_cloudwatch_log_group)
#
# OKE publishes control-plane logs as an OCI Logging service log (service
# "oke-k8s-cp-prod", resource type "clusterscluster"), not a managed cluster
# attribute - unlike EKS, which flips log types on directly on the cluster
# resource. This module creates a dedicated log group and one log per enabled
# category, both off by default.
################################################################################

locals {
  create_control_plane_log_group = local.create && var.create_control_plane_log_group
  control_plane_log_categories   = local.create_control_plane_log_group ? toset(var.control_plane_enabled_log_categories) : toset([])
}

resource "oci_logging_log_group" "control_plane" {
  count = local.create_control_plane_log_group ? 1 : 0

  compartment_id = var.compartment_id
  display_name   = "${var.name}-control-plane"
  description    = "OKE control-plane logs for cluster ${var.name}."

  freeform_tags = merge({ "Name" = "${var.name}-control-plane" }, var.tags, var.control_plane_log_group_tags)
  defined_tags  = merge(var.defined_tags, var.control_plane_log_group_defined_tags)

  lifecycle {
    ignore_changes = [defined_tags, freeform_tags]
  }
}

resource "oci_logging_log" "control_plane" {
  for_each = local.control_plane_log_categories

  display_name       = "${var.name}-${each.value}"
  log_group_id       = oci_logging_log_group.control_plane[0].id
  log_type           = "SERVICE"
  is_enabled         = true
  retention_duration = var.control_plane_log_retention_duration

  configuration {
    source {
      category    = each.value
      resource    = local.cluster_id
      service     = "oke-k8s-cp-prod"
      source_type = "OCISERVICE"
    }
  }

  freeform_tags = merge({ "Name" = "${var.name}-${each.value}" }, var.tags, var.control_plane_log_group_tags)
  defined_tags  = merge(var.defined_tags, var.control_plane_log_group_defined_tags)
}
