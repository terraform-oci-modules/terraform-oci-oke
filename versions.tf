terraform {
  required_version = ">= 1.7"

  required_providers {
    oci = {
      source = "oracle/oci"
      # 8.16.0 sends security_attributes in UpdateClusterEndpointConfig for all
      # clusters, but the OKE API only accepts it for NPN CNI, flannel clusters
      # get a 400. Remove the upper bound once a fixed version is released.
      version = ">= 6.0, < 8.16.0"
    }
  }
}
