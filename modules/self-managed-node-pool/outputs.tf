locals {
  instance_pool = try(
    oci_core_instance_pool.autoscaled[0],
    oci_core_instance_pool.managed[0],
    null,
  )
}

output "id" {
  description = "OCID of the instance pool."
  value       = try(local.instance_pool.id, null)
}

output "instance_configuration_id" {
  description = "OCID of the instance configuration."
  value       = oci_core_instance_configuration.this.id
}

output "instance_pool" {
  description = "All attributes of the instance pool."
  value       = local.instance_pool
}
