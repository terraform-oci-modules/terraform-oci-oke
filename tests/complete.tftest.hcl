run "creates_complete_cluster" {
  command = apply

  module {
    source = "./examples/complete"
  }

  assert {
    condition     = output.cluster_id != null
    error_message = "Enhanced OKE cluster must be created"
  }
  assert {
    condition     = output.cluster_oidc_discovery_endpoint != null
    error_message = "OIDC discovery endpoint must be enabled and returned"
  }
  assert {
    condition     = length(output.node_pool_ids) == 1
    error_message = "Managed node pool must be created"
  }
  assert {
    condition     = length(output.virtual_node_pool_ids) == 1
    error_message = "Virtual node pool must be created"
  }
  assert {
    condition     = length(output.cluster_addons) == 1
    error_message = "CoreDNS addon must be created"
  }
}
