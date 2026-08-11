output "cluster_id" {
  description = "The OCID of the OKE cluster"
  value       = module.oke.cluster_id
}

output "cluster_addons" {
  description = "The OKE-managed addons that were enabled"
  value       = module.oke.cluster_addons
}

output "node_pool_ids" {
  description = "The OCIDs of the managed node pools"
  value       = module.oke.node_pool_ids
}
