################################################################################
# Mock unit tests: fast, free, no real OCI resources.
#
# Exercises input->config mappings and the recommended-NSG-ruleset logic against
# the module root with a mocked OCI provider (command = plan). Run on its own:
#   terraform test -filter=tests/unit_mappings.tftest.hcl
################################################################################

mock_provider "oci" {
  mock_data "oci_identity_availability_domains" {
    defaults = {
      availability_domains = [
        { name = "AD-1" },
        { name = "AD-2" },
        { name = "AD-3" },
      ]
    }
  }

  mock_data "oci_core_services" {
    defaults = {
      services = [{ cidr_block = "all-iad-services-in-oracle-services-network" }]
    }
  }

  mock_data "oci_containerengine_node_pool_option" {
    defaults = {
      sources = [{
        image_id    = "ocid1.image.oc1..aaaaaaaaoke"
        source_name = "Oracle-Linux-8-OKE-1.30.1-100"
      }]
    }
  }

  mock_data "oci_containerengine_addon_options" {
    defaults = {
      addon_options = [{ name = "CertManager" }]
    }
  }

  mock_data "oci_containerengine_cluster_kube_config" {
    defaults = {
      content = ""
    }
  }
}

variables {
  compartment_id          = "ocid1.compartment.oc1..aaaaaaaaunit"
  vcn_id                  = "ocid1.vcn.oc1..aaaaaaaaunit"
  control_plane_subnet_id = "ocid1.subnet.oc1..aaaaaaaacp"
  service_lb_subnet_id    = "ocid1.subnet.oc1..aaaaaaaalb"
  worker_subnet_id        = "ocid1.subnet.oc1..aaaaaaaawk"
  kubernetes_version      = "v1.30.1"
}

# --- Cluster config mappings -------------------------------------------------

run "cluster_type_enhanced_maps_to_api_enum" {
  command = plan

  variables {
    cluster_type = "enhanced"
  }

  assert {
    condition     = oci_containerengine_cluster.this[0].type == "ENHANCED_CLUSTER"
    error_message = "cluster_type = enhanced must map to ENHANCED_CLUSTER"
  }
}

run "cni_flannel_maps_to_api_enum" {
  command = plan

  assert {
    condition     = oci_containerengine_cluster.this[0].cluster_pod_network_options[0].cni_type == "FLANNEL_OVERLAY"
    error_message = "cni_type = flannel must map to FLANNEL_OVERLAY"
  }
}

run "enable_ipv6_adds_dual_stack" {
  command = plan

  variables {
    enable_ipv6 = true
  }

  assert {
    condition     = contains(oci_containerengine_cluster.this[0].options[0].ip_families, "IPv6")
    error_message = "enable_ipv6 must add IPv6 to the cluster ip_families"
  }
}

# --- Recommended NSG ruleset -------------------------------------------------

run "recommended_worker_rules_generated_when_enabled" {
  command = plan

  variables {
    create_worker_nsg                   = true
    worker_nsg_enable_recommended_rules = true
  }

  assert {
    condition     = contains(keys(oci_core_network_security_group_security_rule.worker_recommended), "egress-osn")
    error_message = "recommended worker ruleset must include the OSN egress rule"
  }

  assert {
    condition     = contains(keys(oci_core_network_security_group_security_rule.worker_recommended), "ingress-icmp")
    error_message = "recommended worker ruleset must include the ICMP path-discovery ingress rule"
  }

  assert {
    condition     = contains(keys(oci_core_network_security_group_security_rule.worker_recommended), "egress-internet")
    error_message = "recommended worker ruleset must include the internet egress rule by default"
  }
}

run "recommended_worker_rules_suppressed_when_disabled" {
  command = plan

  variables {
    create_worker_nsg                   = true
    worker_nsg_enable_recommended_rules = false
  }

  assert {
    condition     = length(oci_core_network_security_group_security_rule.worker_recommended) == 0
    error_message = "recommended worker rules must be empty when the flag is off"
  }
}

run "internet_egress_can_be_dropped" {
  command = plan

  variables {
    create_worker_nsg            = true
    worker_allow_internet_egress = false
  }

  assert {
    condition     = !contains(keys(oci_core_network_security_group_security_rule.worker_recommended), "egress-internet")
    error_message = "worker_allow_internet_egress = false must drop the internet egress rule"
  }
}

run "control_plane_allowed_cidrs_open_apiserver" {
  command = plan

  variables {
    create_control_plane_nsg    = true
    control_plane_allowed_cidrs = ["203.0.113.0/24"]
  }

  assert {
    condition     = contains(keys(oci_core_network_security_group_security_rule.control_plane_recommended), "ingress-apiserver-203.0.113.0/24")
    error_message = "control_plane_allowed_cidrs must produce a 6443 ingress rule per CIDR"
  }
}

# --- Per-pool node_metadata (B3) wiring --------------------------------------

run "managed_pool_accepts_per_pool_node_metadata" {
  command = plan

  variables {
    worker_metadata = { global = "g" }
    node_pools = {
      app = {
        shape         = "VM.Standard.E4.Flex"
        node_metadata = { pool = "p" }
      }
    }
  }

  # Reaching the assert proves node_pools accepts node_metadata (type-checked)
  # and that node-pools.tf merges it with the global map without a plan error.
  assert {
    condition     = var.node_pools["app"].node_metadata["pool"] == "p"
    error_message = "node_pools must expose a per-pool node_metadata map"
  }
}

# --- Typed rule / OIDC inputs ----------------------------------------------

run "typed_worker_ingress_rule_maps_to_resource" {
  command = plan

  variables {
    create_worker_nsg = true
    worker_nsg_ingress_rules = {
      https = {
        protocol    = "6"
        source      = "10.0.0.0/16"
        tcp_options = { min = 443, max = 443 }
      }
    }
  }

  assert {
    condition     = oci_core_network_security_group_security_rule.worker_ingress["https"].source_type == "CIDR_BLOCK"
    error_message = "source_type must default to CIDR_BLOCK"
  }

  assert {
    condition     = oci_core_network_security_group_security_rule.worker_ingress["https"].tcp_options[0].destination_port_range[0].min == 443
    error_message = "tcp_options.min must map to destination_port_range.min"
  }
}

run "typed_oidc_config_maps_required_claims" {
  command = plan

  variables {
    enable_oidc_token_auth = true
    oidc_token_authentication_config = {
      issuer_url      = "https://issuer.example.com"
      client_id       = "oke"
      required_claims = [{ key = "aud", value = "oke" }]
    }
  }

  assert {
    condition     = oci_containerengine_cluster.this[0].options[0].open_id_connect_token_authentication_config[0].issuer_url == "https://issuer.example.com"
    error_message = "issuer_url must reach the cluster OIDC config"
  }

  assert {
    condition     = oci_containerengine_cluster.this[0].options[0].open_id_connect_token_authentication_config[0].required_claims[0].key == "aud"
    error_message = "required_claims must map to required_claims blocks"
  }
}

# --- Virtual node pool cycling -----------------------------------------------

run "virtual_pool_node_cycling_reaches_resource" {
  command = plan

  variables {
    cluster_type  = "enhanced"
    cni_type      = "npn"
    pod_subnet_id = "ocid1.subnet.oc1..aaaaaaaapod"
    virtual_node_pools = {
      vnp = {
        node_cycling = { enabled = true, maximum_surge = "2" }
      }
    }
  }

  assert {
    condition     = output.virtual_node_pools["vnp"].virtual_node_pool_cycling_details[0].maximum_surge == "2"
    error_message = "virtual_node_pools[*].node_cycling must reach virtual_node_pool_cycling_details"
  }
  assert {
    condition     = output.virtual_node_pools["vnp"].virtual_node_pool_cycling_details[0].maximum_unavailable == "0"
    error_message = "maximum_unavailable must default to OCI's 0"
  }
}

run "virtual_pool_node_cycling_rejects_bad_value" {
  command = plan

  variables {
    cluster_type  = "enhanced"
    cni_type      = "npn"
    pod_subnet_id = "ocid1.subnet.oc1..aaaaaaaapod"
    virtual_node_pools = {
      vnp = {
        node_cycling = { enabled = true, maximum_unavailable = "-1" }
      }
    }
  }

  expect_failures = [var.virtual_node_pools]
}
