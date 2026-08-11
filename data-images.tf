################################################################################
# Worker image discovery
#
# Resolves an OKE platform image OCID for node pools that do not set image_id
# explicitly, based on the pool's Kubernetes version and CPU architecture (derived
# from the shape). Port of the old terraform-oci-oke image-indexing logic.
################################################################################

data "oci_containerengine_node_pool_option" "this" {
  count = local.create ? 1 : 0

  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}

locals {
  node_pool_images = try(data.oci_containerengine_node_pool_option.this[0].sources, [])

  # Index images by OCID with parsed metadata (arch, OKE k8s version, sort key).
  indexed_images = {
    for img in local.node_pool_images : img.image_id => merge(
      try(element(regexall("OKE-(?P<k8s_version>[0-9\\.]+)-(?P<build>[0-9]+)", img.source_name), 0), { k8s_version = "none" }),
      {
        arch       = length(regexall("aarch64", img.source_name)) > 0 ? "aarch64" : "x86_64"
        image_type = length(regexall("OKE", img.source_name)) > 0 ? "oke" : "platform"
        is_gpu     = length(regexall("GPU", img.source_name)) > 0
        sort_key   = img.source_name
      },
    )
  }

  # All pools that need a worker image (managed + self-managed).
  image_pools = merge(var.node_pools, var.self_managed_node_pools)

  # image_id selector: given a Kubernetes version + arch + GPU class, pick the
  # newest matching OKE image. The GPU dimension is essential: a GPU image only
  # boots on a GPU shape and vice versa, so a plain (CPU) shape must never resolve
  # to a "...-GPU-..." image (and the reverse).
  select_image = {
    for key in distinct([
      for k, v in local.image_pools : format("%s/%s/%s",
        trimprefix(lower(coalesce(v.kubernetes_version, var.kubernetes_version)), "v"),
        length(regexall("A1|A2", v.shape)) > 0 ? "aarch64" : "x86_64",
        length(regexall("GPU", v.shape)) > 0 ? "gpu" : "cpu",
      )
      ]) : key => try(element(reverse(sort([
        for id, meta in local.indexed_images : meta.sort_key
        if meta.image_type == "oke"
        && meta.arch == split("/", key)[1]
        && (meta.is_gpu ? "gpu" : "cpu") == split("/", key)[2]
        && trimprefix(lower(meta.k8s_version), "v") == split("/", key)[0]
    ])), 0), null)
  }

  # Reverse map: sort_key (source_name) → image_id.
  image_by_sort_key = { for id, meta in local.indexed_images : meta.sort_key => id }
}
