output "cluster_id" {
  description = "The OCID of the OKE cluster"
  value       = module.oke.cluster_id
}

output "node_pool_ids" {
  description = "The OCIDs of the managed node pools"
  value       = module.oke.node_pool_ids
}

output "cluster_service_cidr" {
  description = "Resolved Kubernetes service CIDR block"
  value       = module.oke.cluster_service_cidr
}

output "cluster_ip_families" {
  description = "Resolved IP families for the cluster"
  value       = module.oke.cluster_ip_families
}

output "autoscaled_pool_secondary_vnics" {
  description = "Secondary VNIC attachments on the autoscaled pool's node_pool resource"
  value       = module.oke.node_pools["autoscaled"].secondary_vnics
}
