terraform {
  required_version = ">= 1.7"

  required_providers {
    oci = {
      source = "oracle/oci"
      # 8.21.0 adds virtual_node_pool_cycling_details.
      version = ">= 8.21.0"
    }
  }
}
