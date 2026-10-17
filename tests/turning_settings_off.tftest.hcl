################################################################################
# Mock unit tests: fast, free, no real OCI resources.
#
# Turning a setting off on an existing cluster or pool. Control plane and node
# pool ZPR attributes and the node pool / virtual node pool cycling blocks are
# optional and computed in the OCI provider: sending null (or no block) keeps the
# current value. So the module sends nothing by default, and sends an explicit
# "off" (security_attributes = {}, node_cycling.enabled = false) when asked.
# The first run turns everything on; later runs share its state. Run on its own:
#   terraform test -filter=tests/turning_settings_off.tftest.hcl
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
  pod_subnet_id           = "ocid1.subnet.oc1..aaaaaaaapod"
  kubernetes_version      = "v1.30.1"
  cluster_type            = "enhanced"
  cni_type                = "npn"
}

run "everything_on" {
  command = apply

  variables {
    control_plane_security_attributes = { "oracle-zpr.sensitivity.value" = "low" }
    node_pools = {
      np = {
        shape               = "VM.Standard.E4.Flex"
        security_attributes = { "oracle-zpr.sensitivity.value" = "low" }
        node_cycling        = { enabled = true }
      }
    }
    virtual_node_pools = {
      vnp = { node_cycling = { enabled = true } }
    }
  }

  assert {
    condition     = output.node_pools["np"].node_pool_cycling_details[0].is_node_cycling_enabled == true
    error_message = "node cycling must be on after the first apply"
  }
}

run "explicit_off_reaches_the_resources" {
  command = plan

  variables {
    control_plane_security_attributes = {}
    node_pools = {
      np = {
        shape               = "VM.Standard.E4.Flex"
        security_attributes = {}
        node_cycling        = { enabled = false }
      }
    }
    virtual_node_pools = {
      vnp = { node_cycling = { enabled = false } }
    }
  }

  assert {
    condition     = length(oci_containerengine_cluster.this[0].endpoint_config[0].security_attributes) == 0
    error_message = "control_plane_security_attributes = {} must clear the endpoint attributes"
  }
  assert {
    condition     = length(output.node_pools["np"].primary_vnic[0].security_attributes) == 0
    error_message = "security_attributes = {} must send an empty map to the node VNICs"
  }
  assert {
    condition     = output.node_pools["np"].node_pool_cycling_details[0].is_node_cycling_enabled == false
    error_message = "node_cycling.enabled = false must send is_node_cycling_enabled = false"
  }
  assert {
    condition     = output.virtual_node_pools["vnp"].virtual_node_pool_cycling_details[0].is_virtual_node_cycling_enabled == false
    error_message = "node_cycling.enabled = false must send is_virtual_node_cycling_enabled = false"
  }
}

# New pools (np2, vnp2) show what a default config sends: nothing.
# command = apply: the pool outputs are unknown at plan time under the mock.
run "defaults_send_nothing" {
  command = apply

  variables {
    node_pools = {
      np2 = { shape = "VM.Standard.E4.Flex" }
    }
    virtual_node_pools = {
      vnp2 = {}
    }
  }

  assert {
    condition     = length(output.node_pools["np2"].primary_vnic) == 0
    error_message = "by default no primary_vnic block must be sent"
  }
  assert {
    condition     = length(output.node_pools["np2"].node_pool_cycling_details) == 0
    error_message = "by default no node_pool_cycling_details block must be sent"
  }
  assert {
    condition     = length(output.virtual_node_pools["vnp2"].virtual_node_pool_cycling_details) == 0
    error_message = "by default no virtual_node_pool_cycling_details block must be sent"
  }
}

run "disabled_cycling_sends_nothing_on_basic_clusters" {
  command = apply

  variables {
    cluster_type       = "basic"
    cni_type           = "flannel"
    virtual_node_pools = {}
    node_pools = {
      np3 = {
        shape        = "VM.Standard.E4.Flex"
        node_cycling = { enabled = false }
      }
    }
  }

  assert {
    condition     = length(output.node_pools["np3"].node_pool_cycling_details) == 0
    error_message = "basic clusters have no node cycling, so enabled = false must send nothing"
  }
}
