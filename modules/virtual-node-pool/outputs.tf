output "id" {
  description = "OCID of the virtual node pool."
  value       = oci_containerengine_virtual_node_pool.this.id
}

output "name" {
  description = "Display name of the virtual node pool."
  value       = oci_containerengine_virtual_node_pool.this.display_name
}

output "virtual_node_pool" {
  description = "All attributes of the virtual node pool."
  value       = oci_containerengine_virtual_node_pool.this
}
