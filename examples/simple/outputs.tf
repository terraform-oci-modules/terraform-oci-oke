output "cluster_id" {
  description = "The OCID of the OKE cluster"
  value       = module.oke.cluster_id
}

output "cluster_endpoints" {
  description = "The endpoints of the OKE cluster"
  value       = module.oke.cluster_endpoints
}

output "node_pool_ids" {
  description = "The OCIDs of the managed node pools"
  value       = module.oke.node_pool_ids
}

output "vcn_id" {
  description = "The OCID of the supporting VCN"
  value       = module.vcn.vcn_id
}
