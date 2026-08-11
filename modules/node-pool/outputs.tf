locals {
  node_pool = try(
    oci_containerengine_node_pool.autoscaled[0],
    oci_containerengine_node_pool.managed[0],
    null,
  )
}

output "id" {
  description = "OCID of the node pool."
  value       = try(local.node_pool.id, null)
}

output "name" {
  description = "Name of the node pool."
  value       = try(local.node_pool.name, null)
}

output "node_pool" {
  description = "All attributes of the node pool."
  value       = local.node_pool
}
