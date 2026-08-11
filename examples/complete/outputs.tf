output "cluster_id" {
  description = "The OCID of the OKE cluster"
  value       = module.oke.cluster_id
}

output "cluster_endpoints" {
  description = "The endpoints of the OKE cluster"
  value       = module.oke.cluster_endpoints
}

output "cluster_oidc_discovery_endpoint" {
  description = "The OIDC discovery endpoint of the cluster"
  value       = module.oke.cluster_oidc_discovery_endpoint
}

output "node_pool_ids" {
  description = "The OCIDs of the managed node pools"
  value       = module.oke.node_pool_ids
}

output "virtual_node_pool_ids" {
  description = "The OCIDs of the virtual node pools"
  value       = module.oke.virtual_node_pool_ids
}

output "cluster_addons" {
  description = "The OKE-managed addons"
  value       = module.oke.cluster_addons
}
