variable "compartment_id" {
  description = "The OCID of the compartment where resources will be created"
  type        = string
}

variable "ssh_authorized_keys" {
  description = "SSH public key string to authorize on worker nodes"
  type        = string
  default     = null
}
