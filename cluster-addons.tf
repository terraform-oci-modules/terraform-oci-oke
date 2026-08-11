################################################################################
# Cluster Addons  (maps to aws_eks_addon / var.addons)
#
# OKE-managed addons (oci_containerengine_addon). Supported only on ENHANCED
# clusters. The supported addon list is discovered per Kubernetes version.
################################################################################

data "oci_containerengine_addon_options" "this" {
  count = local.create ? 1 : 0

  kubernetes_version = var.kubernetes_version
}

locals {
  supported_addons = try([for o in data.oci_containerengine_addon_options.this[0].addon_options : o.name], [])

  addons = local.create ? var.addons : {}
}

resource "oci_containerengine_addon" "this" {
  for_each = local.addons

  depends_on = [oci_containerengine_cluster.this]

  addon_name                       = each.key
  cluster_id                       = local.cluster_id
  remove_addon_resources_on_delete = each.value.remove_addon_resources_on_delete
  override_existing                = each.value.override_existing
  version                          = each.value.version

  dynamic "configurations" {
    for_each = each.value.configurations
    content {
      key   = tostring(configurations.value.key)
      value = tostring(configurations.value.value)
    }
  }

  timeouts {
    create = each.value.timeouts.create
    update = each.value.timeouts.update
    delete = each.value.timeouts.delete
  }

  lifecycle {
    precondition {
      condition     = local.cluster_type_api == "ENHANCED_CLUSTER"
      error_message = "Cluster addons (addons) require cluster_type = \"enhanced\"."
    }

    precondition {
      condition     = contains(local.supported_addons, each.key)
      error_message = "Addon ${each.key} is not supported for kubernetes_version ${var.kubernetes_version}. Supported: ${join(", ", local.supported_addons)}."
    }
  }
}

################################################################################
# Addon removal  (maps to the old module's addons_to_remove)
#
# Disables OKE-installed default addons via `oci ce cluster disable-addon`. Uses
# the built-in terraform_data resource + local-exec, so it needs the OCI CLI on
# the apply host (no operator host / null provider). One-way at apply time:
# removing a key does not re-enable the addon.
################################################################################

resource "terraform_data" "remove_addon" {
  for_each = local.create ? var.addons_to_remove : {}

  depends_on = [oci_containerengine_addon.this]

  triggers_replace = [each.key, each.value.remove_k8s_resources]

  provisioner "local-exec" {
    command = "oci ce cluster disable-addon --addon-name ${each.key} --cluster-id ${local.cluster_id} --is-remove-existing-add-on ${each.value.remove_k8s_resources} --force"
  }

  lifecycle {
    precondition {
      condition     = local.cluster_type_api == "ENHANCED_CLUSTER"
      error_message = "Cluster addon removal (addons_to_remove) requires cluster_type = \"enhanced\"."
    }

    precondition {
      condition     = contains(local.supported_addons, each.key)
      error_message = "Addon ${each.key} is not a recognized OKE addon for kubernetes_version ${var.kubernetes_version}. Supported: ${join(", ", local.supported_addons)}."
    }
  }
}
