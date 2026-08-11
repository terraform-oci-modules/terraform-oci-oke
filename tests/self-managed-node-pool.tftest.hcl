run "creates_self_managed_node_pool" {
  command = apply

  module {
    source = "./examples/self-managed-node-pool"
  }

  assert {
    condition     = output.cluster_id != null
    error_message = "OKE cluster must be created"
  }
  assert {
    condition     = length(output.self_managed_node_pool_ids) == 1
    error_message = "Self-managed instance pool must be created"
  }
}
