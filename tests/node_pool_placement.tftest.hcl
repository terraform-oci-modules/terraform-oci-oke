################################################################################
# Mock unit tests for node pool placement and ZPR attributes.
#
# compute_cluster_id (RDMA / GPU clusters) and host_group_id (dedicated hosts)
# each live in one availability domain, so the pool must use a single AD.
# security_attributes go on each node's primary VNIC and are only sent when set.
# placement_configs is a set, so it is read with a for expression, not an index.
################################################################################

mock_provider "oci" {}

variables {
  name                 = "np"
  cluster_id           = "ocid1.cluster.oc1..aaaaaaaaunit"
  compartment_id       = "ocid1.compartment.oc1..aaaaaaaaunit"
  kubernetes_version   = "v1.36.4"
  cni_type             = "flannel"
  cluster_type         = "enhanced"
  shape                = "BM.GPU.H100.8"
  image_id             = "ocid1.image.oc1..aaaaaaaaunit"
  availability_domains = ["AD-1"]
  subnet_id            = "ocid1.subnet.oc1..aaaaaaaaunit"
}

run "placement_omitted_by_default" {
  command = plan
  module { source = "./modules/node-pool" }

  assert {
    condition     = oci_containerengine_node_pool.managed[0].node_config_details[0].compute_cluster_id == null
    error_message = "compute_cluster_id must not be sent unless set"
  }
  assert {
    condition     = one([for p in oci_containerengine_node_pool.managed[0].node_config_details[0].placement_configs : p.host_group_id]) == null
    error_message = "host_group_id must not be sent unless set"
  }
  assert {
    condition     = length(oci_containerengine_node_pool.managed[0].primary_vnic) == 0
    error_message = "primary_vnic must not be sent without security_attributes"
  }
}

run "compute_cluster_reaches_node_config" {
  command = plan
  module { source = "./modules/node-pool" }
  variables { compute_cluster_id = "ocid1.computecluster.oc1..aaaaaaaaunit" }

  assert {
    condition     = oci_containerengine_node_pool.managed[0].node_config_details[0].compute_cluster_id == "ocid1.computecluster.oc1..aaaaaaaaunit"
    error_message = "compute_cluster_id must reach node_config_details"
  }
}

run "host_group_reaches_placement_config" {
  command = plan
  module { source = "./modules/node-pool" }
  variables {
    autoscale     = true
    host_group_id = "ocid1.computehostgroup.oc1..aaaaaaaaunit"
  }

  assert {
    condition     = one([for p in oci_containerengine_node_pool.autoscaled[0].node_config_details[0].placement_configs : p.host_group_id]) == "ocid1.computehostgroup.oc1..aaaaaaaaunit"
    error_message = "host_group_id must reach placement_configs on the autoscaled pool too"
  }
}

run "compute_cluster_rejects_multiple_ads" {
  command = plan
  module { source = "./modules/node-pool" }
  variables {
    availability_domains = ["AD-1", "AD-2"]
    compute_cluster_id   = "ocid1.computecluster.oc1..aaaaaaaaunit"
  }

  expect_failures = [oci_containerengine_node_pool.managed]
}

run "host_group_rejects_multiple_ads" {
  command = plan
  module { source = "./modules/node-pool" }
  variables {
    availability_domains = ["AD-1", "AD-2"]
    host_group_id        = "ocid1.computehostgroup.oc1..aaaaaaaaunit"
  }

  expect_failures = [oci_containerengine_node_pool.managed]
}

run "security_attributes_reach_primary_vnic" {
  command = plan
  module { source = "./modules/node-pool" }
  variables {
    security_attributes = {
      "oracle-zpr.sensitivity.value" = "low"
      "oracle-zpr.sensitivity.mode"  = "enforce"
    }
  }

  assert {
    condition     = oci_containerengine_node_pool.managed[0].primary_vnic[0].security_attributes["oracle-zpr.sensitivity.mode"] == "enforce"
    error_message = "security_attributes must reach the primary VNIC"
  }
}
