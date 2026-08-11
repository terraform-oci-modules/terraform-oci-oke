variable "name" {
  description = "Name of the self-managed pool (the self_managed_node_pools map key)."
  type        = string
}

variable "compartment_id" {
  description = "Compartment OCID in which to create the instance configuration and pool."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version advertised to nodes via metadata."
  type        = string
}

variable "apiserver_private_host" {
  description = "Private API server host injected into node metadata for cluster join."
  type        = string
  default     = null
}

variable "cluster_ca_cert" {
  description = "Base64 cluster CA certificate injected into node metadata for cluster join."
  type        = string
  default     = null
}

variable "kubeproxy_mode" {
  description = "kube-proxy mode injected into node metadata."
  type        = string
  default     = "iptables"
}

variable "ssh_public_key" {
  description = "SSH public key authorized on nodes."
  type        = string
  default     = null
}

variable "cloud_init" {
  description = "Base64-encoded cloud-init user_data for node bootstrap."
  type        = string
  default     = null
}

variable "shape" {
  description = "Compute shape for nodes, e.g. \"VM.Standard.E4.Flex\"."
  type        = string
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
  description = "Number of instances in the pool."
  type        = number
  default     = 1
}

variable "autoscale" {
  description = "When true, the pool size is externally managed and ignored by Terraform."
  type        = bool
  default     = false
  nullable    = false
}

variable "image_id" {
  description = "OCID of the node image."
  type        = string
}

variable "boot_volume_size" {
  description = "Boot volume size in GBs."
  type        = number
  default     = 50
}

variable "availability_domains" {
  description = "Resolved availability domain names for placement."
  type        = list(string)
}

variable "placement_fds" {
  description = "Fault domains to constrain placement to, or null for automatic."
  type        = list(string)
  default     = null
}

variable "subnet_id" {
  description = "Primary VNIC subnet OCID."
  type        = string
}

variable "nsg_ids" {
  description = "NSG OCIDs applied to node VNICs."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "assign_public_ip" {
  description = "Assign a public IP to node primary VNICs."
  type        = bool
  default     = false
  nullable    = false
}

variable "node_labels" {
  description = "Kubernetes labels advertised via metadata."
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

variable "node_metadata" {
  description = "Additional instance metadata merged into the launch details."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "freeform_tags" {
  description = "Freeform tags applied to the instance configuration and pool."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "defined_tags" {
  description = "Defined tags applied to the instance configuration and pool."
  type        = map(string)
  default     = {}
  nullable    = false
}
