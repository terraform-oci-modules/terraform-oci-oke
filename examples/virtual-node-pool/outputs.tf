output "cluster_id" {
  description = "The OCID of the OKE cluster"
  value       = module.oke.cluster_id
}

output "virtual_node_pool_ids" {
  description = "The OCIDs of the virtual node pools"
  value       = module.oke.virtual_node_pool_ids
}
