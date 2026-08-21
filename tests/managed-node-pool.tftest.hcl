run "creates_managed_node_pools" {
  command = apply

  module {
    source = "./examples/managed-node-pool"
  }

  assert {
    condition     = output.cluster_id != null
    error_message = "OKE cluster must be created"
  }
  assert {
    condition     = length(output.node_pool_ids) == 2
    error_message = "Both managed node pools (fixed + autoscaled) must be created"
  }
  assert {
    condition     = output.cluster_service_cidr != null
    error_message = "Cluster must have a resolved service CIDR"
  }
  assert {
    condition     = length(output.cluster_ip_families) > 0
    error_message = "Cluster must have at least one resolved IP family"
  }
}
