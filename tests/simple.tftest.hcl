run "creates_simple_cluster" {
  command = apply

  module {
    source = "./examples/simple"
  }

  assert {
    condition     = output.cluster_id != null
    error_message = "OKE cluster must be created"
  }
  assert {
    condition     = output.vcn_id != null
    error_message = "Supporting VCN must be created"
  }
  assert {
    condition     = length(output.node_pool_ids) == 1
    error_message = "Exactly one managed node pool must be created"
  }
  assert {
    condition     = output.cluster_endpoints != null
    error_message = "Cluster endpoints must be returned"
  }
}
