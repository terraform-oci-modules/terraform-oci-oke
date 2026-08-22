output "cluster_id" {
  description = "The OCID of the OKE cluster"
  value       = module.oke.cluster_id
}

output "control_plane_log_group_id" {
  description = "The OCID of the control-plane log group"
  value       = module.oke.control_plane_log_group_id
}

output "control_plane_log_ids" {
  description = "Control-plane log OCIDs by category"
  value       = module.oke.control_plane_log_ids
}
