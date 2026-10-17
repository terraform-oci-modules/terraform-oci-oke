run "creates_cluster_with_addons" {
  command = apply

  module {
    source = "./examples/cluster-addons"
  }

  assert {
    condition     = output.cluster_id != null
    error_message = "Enhanced OKE cluster must be created"
  }
  assert {
    condition     = length(output.cluster_addons) == 2
    error_message = "Both optional add-ons (CertManager, KubernetesMetricsServer) must be created"
  }
  assert {
    condition     = length(output.node_pool_ids) == 1
    error_message = "Managed node pool must be created"
  }
}
