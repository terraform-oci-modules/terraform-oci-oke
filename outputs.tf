################################################################################
# Cluster
################################################################################

output "cluster_id" {
  description = "OCID of the OKE cluster. Maps to EKS cluster_id."
  value       = local.cluster_id
}

output "cluster_name" {
  description = "Name of the OKE cluster. Maps to EKS cluster_name."
  value       = try(local.cluster.name, null)
}

output "cluster_kubernetes_version" {
  description = "Kubernetes version of the cluster. Maps to EKS cluster_version."
  value       = try(local.cluster.kubernetes_version, null)
}

output "cluster_endpoints" {
  description = "Public/private endpoints of the cluster. Maps to EKS cluster_endpoint."
  value       = try(local.cluster.endpoints[0], null)
}

output "cluster_state" {
  description = "Lifecycle state of the cluster. Maps to EKS cluster_status."
  value       = try(local.cluster.state, null)
}

output "cluster_all_attributes" {
  description = "All attributes of the cluster resource."
  value       = local.cluster
}

################################################################################
# OIDC / identity
################################################################################

output "cluster_oidc_discovery_endpoint" {
  description = "OIDC discovery endpoint (workload identity). Maps to EKS oidc_provider."
  value       = try(local.cluster.open_id_connect_discovery_endpoint, null)
}

################################################################################
# Kubeconfig (sensitive; only populated when enable_sensitive_outputs = true)
################################################################################

output "kubeconfig" {
  description = "Cluster kubeconfig content. Only populated when enable_sensitive_outputs = true."
  value = var.enable_sensitive_outputs ? try(
    one(data.oci_containerengine_cluster_kube_config.public[*].content),
    one(data.oci_containerengine_cluster_kube_config.private[*].content),
    null,
  ) : null
  sensitive = true
}

output "cluster_ca_certificate" {
  description = "Base64 cluster CA certificate. Only populated when enable_sensitive_outputs = true."
  value       = var.enable_sensitive_outputs ? local.cluster_ca_cert : null
  sensitive   = true
}

output "apiserver_private_host" {
  description = "Private API server host address."
  value       = local.apiserver_private_host
}

################################################################################
# Node pools
################################################################################

output "node_pools" {
  description = "Managed node pools by name. Maps to eks_managed_node_groups."
  value       = { for k, m in module.node_pool : k => m.node_pool }
}

output "node_pool_ids" {
  description = "Managed node pool OCIDs by name."
  value       = { for k, m in module.node_pool : k => m.id }
}

output "virtual_node_pools" {
  description = "Virtual node pools by name. Maps to fargate_profiles."
  value       = { for k, m in module.virtual_node_pool : k => m.virtual_node_pool }
}

output "virtual_node_pool_ids" {
  description = "Virtual node pool OCIDs by name."
  value       = { for k, m in module.virtual_node_pool : k => m.id }
}

output "self_managed_node_pools" {
  description = "Self-managed node pools (instance pools) by name. Maps to self_managed_node_groups."
  value       = { for k, m in module.self_managed_node_pool : k => m.instance_pool }
}

output "self_managed_node_pool_ids" {
  description = "Self-managed instance pool OCIDs by name."
  value       = { for k, m in module.self_managed_node_pool : k => m.id }
}

################################################################################
# Addons
################################################################################

output "cluster_addons" {
  description = "OKE-managed addons by name. Maps to cluster_addons."
  value       = { for k, a in oci_containerengine_addon.this : k => a }
}

################################################################################
# Network Security Groups
################################################################################

output "control_plane_nsg_id" {
  description = "OCID of the control plane NSG created by this module (null when create_control_plane_nsg = false)."
  value       = try(oci_core_network_security_group.control_plane[0].id, null)
}

output "worker_nsg_id" {
  description = "OCID of the worker NSG created by this module (null when create_worker_nsg = false)."
  value       = try(oci_core_network_security_group.worker[0].id, null)
}
