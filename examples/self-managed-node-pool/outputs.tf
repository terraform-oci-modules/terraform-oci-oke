output "cluster_id" {
  description = "The OCID of the OKE cluster"
  value       = module.oke.cluster_id
}

output "self_managed_node_pool_ids" {
  description = "The OCIDs of the self-managed instance pools"
  value       = module.oke.self_managed_node_pool_ids
}
