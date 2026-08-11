output "cluster_id" {
  description = "The OCID of the OKE cluster"
  value       = module.oke.cluster_id
}

output "node_pool_ids" {
  description = "The OCIDs of the managed node pools"
  value       = module.oke.node_pool_ids
}
