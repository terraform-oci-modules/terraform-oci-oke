variable "name" {
  description = "Name of the virtual node pool (the virtual_node_pools map key)."
  type        = string
}

variable "cluster_id" {
  description = "OCID of the OKE cluster this virtual node pool joins."
  type        = string
}

variable "compartment_id" {
  description = "Compartment OCID in which to create the virtual node pool."
  type        = string
}

variable "cluster_type" {
  description = "Cluster type (\"basic\" or \"enhanced\"). Virtual node pools require \"enhanced\"."
  type        = string
}

variable "cni_type" {
  description = "Cluster CNI type. Virtual node pools require \"npn\"."
  type        = string
}

variable "shape" {
  description = "Pod shape, one of Pod.Standard.E3.Flex, Pod.Standard.E4.Flex, Pod.Standard.A1.Flex."
  type        = string
  default     = "Pod.Standard.E4.Flex"
}

variable "size" {
  description = "Number of virtual nodes in the pool."
  type        = number
  default     = 1
}

variable "availability_domains" {
  description = "Resolved availability domain names for placement."
  type        = list(string)
}

variable "subnet_id" {
  description = "Virtual node subnet OCID."
  type        = string
}

variable "fault_domains" {
  description = "Fault domains for virtual node placement."
  type        = list(string)
  default     = ["FAULT-DOMAIN-1", "FAULT-DOMAIN-2", "FAULT-DOMAIN-3"]
  nullable    = false
}

variable "pod_subnet_id" {
  description = "Pod subnet OCID (defaults to subnet_id)."
  type        = string
  default     = null
}

variable "nsg_ids" {
  description = "NSG OCIDs applied to virtual nodes."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "pod_nsg_ids" {
  description = "Pod NSG OCIDs (defaults to nsg_ids)."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "node_labels" {
  description = "Kubernetes labels applied to virtual nodes."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "taints" {
  description = "Taints applied to virtual nodes, keyed by taint key."
  type = map(object({
    value  = optional(string)
    effect = optional(string, "NoSchedule")
  }))
  default  = {}
  nullable = false
}

variable "freeform_tags" {
  description = "Freeform tags applied to the virtual node pool."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "defined_tags" {
  description = "Defined tags applied to the virtual node pool."
  type        = map(string)
  default     = {}
  nullable    = false
}
