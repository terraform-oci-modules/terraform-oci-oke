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
