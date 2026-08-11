run "creates_virtual_node_pool" {
  command = apply

  module {
    source = "./examples/virtual-node-pool"
  }

  assert {
    condition     = output.cluster_id != null
    error_message = "Enhanced OKE cluster must be created"
  }
  assert {
    condition     = length(output.virtual_node_pool_ids) == 1
    error_message = "Virtual node pool must be created"
  }
}
