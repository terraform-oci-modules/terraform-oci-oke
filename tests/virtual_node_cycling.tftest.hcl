################################################################################
# Mock unit tests for virtual node pool cycling.
#
# node_cycling on a virtual pool maps to virtual_node_pool_cycling_details. The
# block is only sent when enabled, and surge/unavailable default to OCI's own
# defaults (1 and 0).
################################################################################

mock_provider "oci" {}

variables {
  name                 = "vnp"
  cluster_id           = "ocid1.cluster.oc1..aaaaaaaaunit"
  compartment_id       = "ocid1.compartment.oc1..aaaaaaaaunit"
  cluster_type         = "enhanced"
  cni_type             = "npn"
  availability_domains = ["AD-1"]
  subnet_id            = "ocid1.subnet.oc1..aaaaaaaaunit"
}

run "cycling_omitted_by_default" {
  command = plan
  module { source = "./modules/virtual-node-pool" }

  assert {
    condition     = length(oci_containerengine_virtual_node_pool.this.virtual_node_pool_cycling_details) == 0
    error_message = "virtual_node_pool_cycling_details must not be sent unless node_cycling.enabled"
  }
}

run "cycling_enabled_uses_oci_defaults" {
  command = plan
  module { source = "./modules/virtual-node-pool" }
  variables { node_cycling = { enabled = true } }

  assert {
    condition     = oci_containerengine_virtual_node_pool.this.virtual_node_pool_cycling_details[0].is_virtual_node_cycling_enabled == true
    error_message = "Enabled node_cycling must set is_virtual_node_cycling_enabled"
  }
  assert {
    condition = (
      oci_containerengine_virtual_node_pool.this.virtual_node_pool_cycling_details[0].maximum_surge == "1" &&
      oci_containerengine_virtual_node_pool.this.virtual_node_pool_cycling_details[0].maximum_unavailable == "0"
    )
    error_message = "Defaults must match OCI's (surge 1, unavailable 0)"
  }
}

run "cycling_accepts_percentages" {
  command = plan
  module { source = "./modules/virtual-node-pool" }
  variables {
    node_cycling = { enabled = true, maximum_surge = "25%", maximum_unavailable = "100%" }
  }

  assert {
    condition     = oci_containerengine_virtual_node_pool.this.virtual_node_pool_cycling_details[0].maximum_surge == "25%"
    error_message = "Percentage surge must pass through unchanged"
  }
}

run "rejects_bad_surge" {
  command = plan
  module { source = "./modules/virtual-node-pool" }
  variables { node_cycling = { enabled = true, maximum_surge = "two" } }

  expect_failures = [var.node_cycling]
}

run "rejects_over_100_percent" {
  command = plan
  module { source = "./modules/virtual-node-pool" }
  variables { node_cycling = { enabled = true, maximum_unavailable = "150%" } }

  expect_failures = [var.node_cycling]
}
