################################################################################
# Shared cluster context (set by the root module)
################################################################################

variable "name" {
  description = "Name of the node pool (the worker_pools map key)."
  type        = string
}

variable "cluster_id" {
  description = "OCID of the OKE cluster this node pool joins."
  type        = string
}

variable "compartment_id" {
  description = "Compartment OCID in which to create the node pool."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the node pool."
  type        = string
}

variable "cni_type" {
  description = "Cluster CNI type: \"flannel\" (FLANNEL_OVERLAY) or \"npn\" (OCI_VCN_IP_NATIVE)."
  type        = string
}

variable "cluster_type" {
  description = "Cluster tier: \"basic\" or \"enhanced\". node_cycling requires \"enhanced\"."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key authorized on worker nodes."
  type        = string
  default     = null
}

variable "apiserver_private_host" {
  description = "Private API server host injected into node_metadata."
  type        = string
  default     = null
}

variable "kubeproxy_mode" {
  description = "kube-proxy mode (iptables or ipvs) injected into node_metadata."
  type        = string
  default     = "iptables"
}

variable "node_metadata" {
  description = "Global node metadata merged into every node pool."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "freeform_tags" {
  description = "Freeform tags applied to the node pool."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "defined_tags" {
  description = "Defined tags applied to the node pool."
  type        = map(string)
  default     = {}
  nullable    = false
}

################################################################################
# Node pool configuration (resolved by the root module)
################################################################################

variable "shape" {
  description = "Compute shape for worker nodes, e.g. \"VM.Standard.E4.Flex\"."
  type        = string
}

variable "network_launch_type" {
  description = "Advanced node pool network launch type override. Provider-validated; leave null for the OCI default."
  type        = string
  default     = null
}

variable "ocpus" {
  description = "OCPUs per node (Flex shapes only)."
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory in GBs per node (Flex shapes only)."
  type        = number
  default     = 16
}

variable "size" {
  description = "Number of nodes in the pool."
  type        = number
  default     = 1
}

variable "autoscale" {
  description = "When true, the node pool size is managed by cluster-autoscaler and ignored by Terraform."
  type        = bool
  default     = false
  nullable    = false
}

variable "image_id" {
  description = "OCID of the worker node image."
  type        = string
}

variable "boot_volume_size" {
  description = "Boot volume size in GBs for worker nodes."
  type        = number
  default     = 50
}

variable "availability_domains" {
  description = "Resolved availability domain names for node placement (one placement_config per entry)."
  type        = list(string)
}

variable "placement_fds" {
  description = "Fault domains to constrain placement to, or null to select automatically."
  type        = list(string)
  default     = null
}

variable "subnet_id" {
  description = "Worker subnet OCID."
  type        = string
}

variable "nsg_ids" {
  description = "NSG OCIDs applied to worker node VNICs."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "pod_subnet_id" {
  description = "Pod subnet OCID (npn CNI only)."
  type        = string
  default     = null
}

variable "pod_nsg_ids" {
  description = "Pod NSG OCIDs (npn CNI only)."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "max_pods_per_node" {
  description = "Maximum pods per node (npn CNI only)."
  type        = number
  default     = 31
}

variable "node_labels" {
  description = "Kubernetes labels applied to nodes."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "volume_kms_key_id" {
  description = "KMS key OCID for boot volume encryption."
  type        = string
  default     = null
}

variable "pv_transit_encryption" {
  description = "Enable in-transit encryption for the boot volume. Defaults to true (secure by default); only applies to paravirtualized attachments."
  type        = bool
  default     = true
  nullable    = false
}

variable "capacity_reservation_id" {
  description = "Compute capacity reservation OCID (requires a single availability domain)."
  type        = string
  default     = null
}

variable "preemptible_config" {
  description = "Preemptible node configuration."
  type = object({
    enable                  = optional(bool, false)
    is_preserve_boot_volume = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "eviction_grace_duration" {
  description = "Node eviction grace duration in seconds (0-3600)."
  type        = number
  default     = 300
  nullable    = false
}

variable "force_node_delete" {
  description = "Force delete nodes after the grace duration."
  type        = bool
  default     = false
  nullable    = false
}

variable "force_node_action" {
  description = "Force the eviction action (cordon/drain) itself after the grace duration, not just the delete. Maps to is_force_action_after_grace_duration."
  type        = bool
  default     = false
  nullable    = false
}

variable "node_cycling" {
  description = "Node pool cycling configuration. Requires cluster_type = \"enhanced\"."
  type = object({
    enabled             = optional(bool, false)
    maximum_surge       = optional(string, "1")
    maximum_unavailable = optional(string, "1")
    cycle_modes         = optional(list(string), ["BOOT_VOLUME_REPLACE"])
  })
  default  = {}
  nullable = false
}

variable "timeouts" {
  description = <<-EOT
    Per-pool create/update/delete timeouts. delete defaults to "75m" - OCI's
    node eviction grace period ceiling is 60m (PT60M) and drains have been
    observed to overrun the provider's own default delete timeout, aborting an
    otherwise-healthy drain. See docs/testing.md.
  EOT
  type = object({
    create = optional(string)
    update = optional(string)
    delete = optional(string, "75m")
  })
  default  = {}
  nullable = false
}
