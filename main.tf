locals {
  create = var.create

  # Resolve AD numbers (1/2/3) → full tenancy-specific AD names for node pools.
  availability_domains = data.oci_identity_availability_domains.this.availability_domains

  # Friendly cluster_type → OCI API enum.
  cluster_type_api = lookup({
    basic    = "BASIC_CLUSTER"
    enhanced = "ENHANCED_CLUSTER"
  }, lower(var.cluster_type), "BASIC_CLUSTER")

  # Friendly CNI selector → OCI API enum. Maps to the EKS CNI/ip_family concept.
  cni_type_api = var.cni_type == "flannel" ? "FLANNEL_OVERLAY" : "OCI_VCN_IP_NATIVE"

  # IP families for the cluster. Maps to the EKS ip_family variable.
  ip_families = length(var.ip_families) > 0 ? var.ip_families : (
    var.enable_ipv6 ? ["IPv4", "IPv6"] : ["IPv4"]
  )

  # Canonical cluster reference (null when create = false).
  cluster    = try(oci_containerengine_cluster.this[0], null)
  cluster_id = try(local.cluster.id, null)

  # Merged control-plane NSG list: user-supplied + the cluster NSG created here.
  control_plane_nsg_ids = compact(concat(
    var.control_plane_nsg_ids,
    var.create_control_plane_nsg ? [oci_core_network_security_group.control_plane[0].id] : [],
  ))

  # Endpoint availability for kubeconfig data sources.
  public_endpoint_available  = local.create && var.control_plane_is_public && var.assign_public_ip_to_control_plane
  private_endpoint_available = local.create

  # Decode kubeconfig content to derive the private apiserver host + CA cert,
  # which node pools inject into node_metadata.
  kubeconfig_private  = try(yamldecode(data.oci_containerengine_cluster_kube_config.private[0].content), tomap({}))
  kubeconfig_clusters = try(local.kubeconfig_private["clusters"], [])
  apiserver_private_host = try(
    split(":", local.cluster.endpoints[0].private_endpoint)[0],
    split(":", replace(local.kubeconfig_clusters[0].cluster.server, "https://", ""))[0],
    null,
  )
  cluster_ca_cert = try(local.kubeconfig_clusters[0].cluster["certificate-authority-data"], null)

  # Tag merge helpers: "Name" first, then global, then per-resource overrides.
  cluster_tags         = merge({ "Name" = var.name }, var.tags, var.cluster_tags)
  cluster_defined_tags = merge(var.defined_tags, var.cluster_defined_tags)

  persistent_volume_tags         = merge(var.tags, var.persistent_volume_tags)
  persistent_volume_defined_tags = merge(var.defined_tags, var.persistent_volume_defined_tags)

  service_lb_tags         = merge(var.tags, var.service_lb_tags)
  service_lb_defined_tags = merge(var.defined_tags, var.service_lb_defined_tags)
}

################################################################################
# Data Sources
################################################################################

data "oci_identity_availability_domains" "this" {
  compartment_id = var.compartment_id
}

# Kubeconfig (private endpoint), always retrievable; drives apiserver host + CA cert.
data "oci_containerengine_cluster_kube_config" "private" {
  count = local.private_endpoint_available ? 1 : 0

  cluster_id = local.cluster_id
  endpoint   = "PRIVATE_ENDPOINT"
}

# Kubeconfig (public endpoint), only when a public API endpoint is enabled.
data "oci_containerengine_cluster_kube_config" "public" {
  count = local.public_endpoint_available ? 1 : 0

  cluster_id = local.cluster_id
  endpoint   = "PUBLIC_ENDPOINT"
}

################################################################################
# Cluster  (maps to aws_eks_cluster)
################################################################################

resource "oci_containerengine_cluster" "this" {
  count = local.create ? 1 : 0

  compartment_id     = var.compartment_id
  name               = var.name
  kubernetes_version = var.kubernetes_version
  type               = local.cluster_type_api
  vcn_id             = var.vcn_id
  kms_key_id         = var.cluster_kms_key_id

  freeform_tags = local.cluster_tags
  defined_tags  = local.cluster_defined_tags

  # Pod networking model: flannel overlay or VCN-native (npn).
  cluster_pod_network_options {
    cni_type = local.cni_type_api
  }

  # Control plane endpoint placement. Maps to EKS vpc_config endpoint_* settings.
  endpoint_config {
    is_public_ip_enabled = var.control_plane_is_public && var.assign_public_ip_to_control_plane
    nsg_ids              = local.control_plane_nsg_ids
    subnet_id            = var.control_plane_subnet_id
  }

  # Secrets encryption with a customer KMS key (maps to EKS encryption_config).
  dynamic "image_policy_config" {
    for_each = var.use_signed_images ? [1] : []

    content {
      is_policy_enabled = true

      dynamic "key_details" {
        for_each = var.image_signing_keys
        content {
          kms_key_id = key_details.value
        }
      }
    }
  }

  options {
    service_lb_subnet_ids = compact([var.service_lb_subnet_id])
    ip_families           = local.ip_families

    kubernetes_network_config {
      pods_cidr     = var.pods_cidr
      services_cidr = var.services_cidr
    }

    persistent_volume_config {
      freeform_tags = local.persistent_volume_tags
      defined_tags  = local.persistent_volume_defined_tags
    }

    service_lb_config {
      backend_nsg_ids = var.service_lb_backend_nsg_ids
      freeform_tags   = local.service_lb_tags
      defined_tags    = local.service_lb_defined_tags
    }

    # OIDC discovery / workload identity (maps loosely to EKS IRSA).
    dynamic "open_id_connect_discovery" {
      for_each = var.enable_oidc_discovery ? [1] : []
      content {
        is_open_id_connect_discovery_enabled = true
      }
    }

    # OIDC token authentication (structured cluster auth).
    dynamic "open_id_connect_token_authentication_config" {
      for_each = var.enable_oidc_token_auth ? [1] : []
      content {
        is_open_id_connect_auth_enabled = true
        issuer_url                      = lookup(var.oidc_token_authentication_config, "issuer_url", null)
        client_id                       = lookup(var.oidc_token_authentication_config, "client_id", null)
        ca_certificate                  = lookup(var.oidc_token_authentication_config, "ca_certificate", null)
        signing_algorithms              = lookup(var.oidc_token_authentication_config, "signing_algorithms", null)
        groups_claim                    = lookup(var.oidc_token_authentication_config, "groups_claim", null)
        groups_prefix                   = lookup(var.oidc_token_authentication_config, "groups_prefix", null)
        username_claim                  = lookup(var.oidc_token_authentication_config, "username_claim", null)
        username_prefix                 = lookup(var.oidc_token_authentication_config, "username_prefix", null)
        configuration_file              = lookup(var.oidc_token_authentication_config, "configuration_file", null)

        dynamic "required_claims" {
          for_each = lookup(var.oidc_token_authentication_config, "required_claims", [])
          content {
            key   = required_claims.value.key
            value = required_claims.value.value
          }
        }
      }
    }
  }

  timeouts {
    create = var.timeouts.create
    update = var.timeouts.update
    delete = var.timeouts.delete
  }

  lifecycle {
    ignore_changes = [
      defined_tags,
      freeform_tags,
      options[0].kubernetes_network_config,
    ]

    precondition {
      condition     = !var.use_signed_images || length(var.image_signing_keys) > 0
      error_message = "Must provide at least one image_signing_keys value when use_signed_images is enabled."
    }

    precondition {
      condition     = var.service_lb_subnet_id != null
      error_message = "service_lb_subnet_id is required for the cluster load balancer subnet."
    }
  }
}
