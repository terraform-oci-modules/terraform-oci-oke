################################################################################
# Mock unit tests for node pool eviction grace duration formatting.
#
# OCI stores eviction_grace_duration in a canonical ISO 8601 form (PT1H, PT5M,
# PT1M30S, PT45S). Emitting any other spelling of the same duration (PT60M,
# PT90S) plans a diff on every run, so the module must emit the canonical form.
################################################################################

mock_provider "oci" {}

variables {
  name                 = "np"
  cluster_id           = "ocid1.cluster.oc1..aaaaaaaaunit"
  compartment_id       = "ocid1.compartment.oc1..aaaaaaaaunit"
  kubernetes_version   = "v1.30.1"
  cni_type             = "flannel"
  cluster_type         = "basic"
  shape                = "VM.Standard.E4.Flex"
  image_id             = "ocid1.image.oc1..aaaaaaaaunit"
  availability_domains = ["AD-1"]
  subnet_id            = "ocid1.subnet.oc1..aaaaaaaaunit"
}

run "one_hour_is_pt1h" {
  command = plan
  module { source = "./modules/node-pool" }
  variables { eviction_grace_duration = 3600 }

  assert {
    condition     = oci_containerengine_node_pool.managed[0].node_eviction_node_pool_settings[0].eviction_grace_duration == "PT1H"
    error_message = "3600 seconds must render as PT1H, not PT60M"
  }
}

run "whole_minutes_are_minutes" {
  command = plan
  module { source = "./modules/node-pool" }
  variables { eviction_grace_duration = 300 }

  assert {
    condition     = oci_containerengine_node_pool.managed[0].node_eviction_node_pool_settings[0].eviction_grace_duration == "PT5M"
    error_message = "300 seconds must render as PT5M"
  }
}

run "minutes_and_seconds_are_split" {
  command = plan
  module { source = "./modules/node-pool" }
  variables { eviction_grace_duration = 90 }

  assert {
    condition     = oci_containerengine_node_pool.managed[0].node_eviction_node_pool_settings[0].eviction_grace_duration == "PT1M30S"
    error_message = "90 seconds must render as PT1M30S, not PT90S"
  }
}

run "under_a_minute_is_seconds" {
  command = plan
  module { source = "./modules/node-pool" }
  variables { eviction_grace_duration = 45 }

  assert {
    condition     = oci_containerengine_node_pool.managed[0].node_eviction_node_pool_settings[0].eviction_grace_duration == "PT45S"
    error_message = "45 seconds must render as PT45S"
  }
}

run "autoscaled_pool_uses_same_formatting" {
  command = plan
  module { source = "./modules/node-pool" }
  variables {
    autoscale               = true
    eviction_grace_duration = 3600
  }

  assert {
    condition     = oci_containerengine_node_pool.autoscaled[0].node_eviction_node_pool_settings[0].eviction_grace_duration == "PT1H"
    error_message = "the autoscaled pool must use the same canonical formatting"
  }
}

run "rejects_over_one_hour" {
  command = plan
  module { source = "./modules/node-pool" }
  variables { eviction_grace_duration = 7200 }

  expect_failures = [var.eviction_grace_duration]
}
