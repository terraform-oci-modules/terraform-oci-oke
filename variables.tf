################################################################################
# General
################################################################################

variable "create" {
  description = "Controls whether resources are created (affects all resources in this module)."
  type        = bool
  default     = true
  nullable    = false
}

variable "compartment_id" {
  description = "The compartment OCID in which to create the cluster and node pools. Maps to AWS account/region scoping."
  type        = string

  validation {
    condition     = can(regex("^ocid1\\.(compartment|tenancy)\\.[a-z0-9.]+", var.compartment_id))
    error_message = "compartment_id must be a valid OCID (ocid1.compartment... or ocid1.tenancy...)."
  }
}

variable "tags" {
  description = "Freeform tags applied to all resources. Maps to the AWS tags variable."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "defined_tags" {
  description = "Defined tags (namespace.key = value) applied to all resources. OCI-only; no AWS equivalent."
  type        = map(string)
  default     = {}
  nullable    = false
}

################################################################################
# Cluster  (maps to aws_eks_cluster inputs)
################################################################################

variable "name" {
  description = "Name of the OKE cluster. Maps to the EKS name variable (the cluster_name output mirrors EKS's output name)."
  type        = string
  default     = "oke"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster, e.g. \"v1.30.1\". Maps to EKS kubernetes_version."
  type        = string
}

variable "cluster_type" {
  description = "OKE cluster tier: \"basic\" or \"enhanced\". Enhanced is required for addons and virtual node pools."
  type        = string
  default     = "basic"

  validation {
    condition     = contains(["basic", "enhanced"], lower(var.cluster_type))
    error_message = "cluster_type must be \"basic\" or \"enhanced\"."
  }
}

variable "vcn_id" {
  description = "OCID of the VCN hosting the cluster. Maps to the EKS vpc_id variable. Supplied by the sibling terraform-oci-vcn module."
  type        = string

  validation {
    condition     = can(regex("^ocid1\\.vcn\\.[a-z0-9.]+", var.vcn_id))
    error_message = "vcn_id must be a valid VCN OCID (ocid1.vcn...)."
  }
}

variable "cluster_kms_key_id" {
  description = "KMS key OCID for Kubernetes secrets encryption. Maps to EKS encryption_config. The key is not created by this module."
  type        = string
  default     = null
}

variable "timeouts" {
  description = "Create/update/delete timeouts for the cluster."
  type = object({
    create = optional(string, "60m")
    update = optional(string, "120m")
    delete = optional(string, "60m")
  })
  default  = {}
  nullable = false
}

################################################################################
# Control plane endpoint & networking  (maps to EKS vpc_config / endpoints)
################################################################################

variable "control_plane_subnet_id" {
  description = "Subnet OCID for the cluster control plane endpoint. Maps to EKS control_plane_subnet_ids."
  type        = string

  validation {
    condition     = can(regex("^ocid1\\.subnet\\.[a-z0-9.]+", var.control_plane_subnet_id))
    error_message = "control_plane_subnet_id must be a valid subnet OCID."
  }
}

variable "control_plane_is_public" {
  description = "Whether the control plane endpoint is reachable publicly. Maps to EKS endpoint_public_access."
  type        = bool
  default     = false
  nullable    = false
}

variable "assign_public_ip_to_control_plane" {
  description = "Assign a public IP to the control plane endpoint (requires control_plane_is_public)."
  type        = bool
  default     = false
  nullable    = false
}

variable "control_plane_nsg_ids" {
  description = "Additional NSG OCIDs for the control plane endpoint. Maps to EKS additional_security_group_ids."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "cni_type" {
  description = "Pod networking model: \"flannel\" (FLANNEL_OVERLAY) or \"npn\" (OCI_VCN_IP_NATIVE). Loosely maps to the EKS CNI/ip_family choice."
  type        = string
  default     = "flannel"

  validation {
    condition     = contains(["flannel", "npn"], var.cni_type)
    error_message = "cni_type must be \"flannel\" or \"npn\"."
  }
}

variable "pods_cidr" {
  description = "CIDR block for pods (flannel only). Maps loosely to EKS pod networking."
  type        = string
  default     = "10.244.0.0/16"
}

variable "services_cidr" {
  description = "CIDR block for Kubernetes services (ClusterIP). Maps to EKS service_ipv4_cidr."
  type        = string
  default     = "10.96.0.0/16"
}

variable "enable_ipv6" {
  description = "Enable IPv4/IPv6 dual-stack on the cluster. Maps to EKS ip_family = ipv6."
  type        = bool
  default     = false
  nullable    = false
}

variable "ip_families" {
  description = "Explicit ip_families list, overriding enable_ipv6 (e.g. [\"IPv4\",\"IPv6\"])."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "service_lb_subnet_id" {
  description = "Subnet OCID for service load balancers. No direct EKS equivalent (EKS uses tagged subnets)."
  type        = string

  validation {
    condition     = can(regex("^ocid1\\.subnet\\.[a-z0-9.]+", var.service_lb_subnet_id))
    error_message = "service_lb_subnet_id must be a valid subnet OCID."
  }
}

variable "service_lb_backend_nsg_ids" {
  description = "NSG OCIDs applied to service load balancer backends."
  type        = list(string)
  default     = []
  nullable    = false
}

################################################################################
# Image signing  (loosely maps to EKS encryption_config intent)
################################################################################

variable "use_signed_images" {
  description = "Enforce signed worker node images via an image policy."
  type        = bool
  default     = false
  nullable    = false
}

variable "image_signing_keys" {
  description = "KMS key OCIDs used to verify signed images (required when use_signed_images = true)."
  type        = list(string)
  default     = []
  nullable    = false
}

################################################################################
# OIDC / workload identity  (maps to EKS IRSA / OIDC)
################################################################################

variable "enable_oidc_discovery" {
  description = "Enable the OIDC discovery endpoint (workload identity). Maps loosely to EKS enable_irsa."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_oidc_token_auth" {
  description = "Enable structured OIDC token authentication on the cluster."
  type        = bool
  default     = false
  nullable    = false
}

variable "oidc_token_authentication_config" {
  description = "OIDC token authentication settings (issuer_url, client_id, ca_certificate, claims, etc.)."
  type        = any
  default     = {}
  nullable    = false
}

################################################################################
# Worker defaults  (shared by node pools)
################################################################################

variable "worker_subnet_id" {
  description = "Default worker subnet OCID for node pools. Maps to EKS subnet_ids."
  type        = string
  default     = null
}

variable "pod_subnet_id" {
  description = "Default pod subnet OCID for npn node pools."
  type        = string
  default     = null
}

variable "worker_nsg_ids" {
  description = "Default NSG OCIDs for worker node VNICs. Maps to EKS node security groups."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "pod_nsg_ids" {
  description = "Default pod NSG OCIDs for npn node pools."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "ssh_authorized_keys" {
  description = "SSH public key authorized on worker nodes. Maps to EKS remote_access keys."
  type        = string
  default     = null
}

variable "kubeproxy_mode" {
  description = "kube-proxy mode for worker nodes: \"iptables\" or \"ipvs\"."
  type        = string
  default     = "iptables"

  validation {
    condition     = contains(["iptables", "ipvs"], var.kubeproxy_mode)
    error_message = "kubeproxy_mode must be \"iptables\" or \"ipvs\"."
  }
}

variable "worker_metadata" {
  description = "Global instance metadata merged into every node pool (per-pool node_metadata is merged on top)."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "worker_tags" {
  description = "Freeform tags applied to all worker pools (merged with var.tags)."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "worker_defined_tags" {
  description = "Defined tags applied to all worker pools (merged with var.defined_tags)."
  type        = map(string)
  default     = {}
  nullable    = false
}

################################################################################
# Per-resource tags
################################################################################

variable "cluster_tags" {
  description = "Additional freeform tags applied to the cluster only."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "cluster_defined_tags" {
  description = "Additional defined tags applied to the cluster only."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "persistent_volume_tags" {
  description = "Freeform tags applied to persistent volumes provisioned by the cluster."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "persistent_volume_defined_tags" {
  description = "Defined tags applied to persistent volumes provisioned by the cluster."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "service_lb_tags" {
  description = "Freeform tags applied to service load balancers provisioned by the cluster."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "service_lb_defined_tags" {
  description = "Defined tags applied to service load balancers provisioned by the cluster."
  type        = map(string)
  default     = {}
  nullable    = false
}

################################################################################
# Network Security Groups (optional, generic)
################################################################################

variable "create_control_plane_nsg" {
  description = "Create a generic NSG for the control plane. Rules are supplied via cluster_nsg_*_rules."
  type        = bool
  default     = false
  nullable    = false
}

variable "create_worker_nsg" {
  description = "Create a generic NSG for workers. Rules are supplied via worker_nsg_*_rules."
  type        = bool
  default     = false
  nullable    = false
}

variable "control_plane_nsg_ingress_rules" {
  description = "Ingress rules for the created control plane NSG, keyed by name."
  type        = any
  default     = {}
  nullable    = false
}

variable "control_plane_nsg_egress_rules" {
  description = "Egress rules for the created control plane NSG, keyed by name."
  type        = any
  default     = {}
  nullable    = false
}

variable "worker_nsg_ingress_rules" {
  description = "Ingress rules for the created worker NSG, keyed by name."
  type        = any
  default     = {}
  nullable    = false
}

variable "worker_nsg_egress_rules" {
  description = "Egress rules for the created worker NSG, keyed by name."
  type        = any
  default     = {}
  nullable    = false
}

variable "control_plane_nsg_enable_recommended_rules" {
  description = "Add the recommended OKE control-plane NSG rules (API/OKE ports 6443/10250/12250, ICMP path discovery, OSN egress, CP inter-comm) to the created cluster NSG. Maps to the EKS node_security_group_enable_recommended_rules concept. Only applies when create_control_plane_nsg = true."
  type        = bool
  default     = true
  nullable    = false
}

variable "worker_nsg_enable_recommended_rules" {
  description = "Add the recommended OKE worker NSG rules (node-to-node, control-plane comms, ICMP path discovery, OSN egress) to the created worker NSG. Maps to the EKS node_security_group_enable_recommended_rules concept. Only applies when create_worker_nsg = true."
  type        = bool
  default     = true
  nullable    = false
}

variable "worker_allow_internet_egress" {
  description = "Add an all-protocol egress-to-internet (0.0.0.0/0) rule to the recommended worker NSG ruleset. Set false for private clusters that reach the internet only via a NAT/service gateway."
  type        = bool
  default     = true
  nullable    = false
}

variable "control_plane_allowed_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API server (TCP 6443). Maps to EKS endpoint_public_access_cidrs, but is enforced through the recommended control-plane NSG ruleset rather than the cluster API, so it has no effect unless create_control_plane_nsg and control_plane_nsg_enable_recommended_rules are both true."
  type        = list(string)
  default     = []
  nullable    = false
}

################################################################################
# Cluster Addons  (maps to aws_eks_addon / var.addons)
################################################################################

variable "addons" {
  description = <<-EOT
    OKE-managed addons to enable, keyed by addon name (e.g. "CertManager",
    "ClusterAutoscaler", "KubernetesMetricsServer"). Requires
    cluster_type = "enhanced". Maps to the EKS addons variable.

    Per addon:
      - version:                          pin a version, or null for latest.
      - override_existing:                take over an addon already installed
                                          out-of-band (e.g. via kubectl/Helm).
      - remove_addon_resources_on_delete: delete the addon's k8s resources on
                                          removal.
      - configurations:                   list of { key, value } pairs from the
                                          addon's schema (string values; richer
                                          config is JSON-in-a-string).

    List the catalog for a version:
      oci ce addon-option list --kubernetes-version <ver> --all --query 'data[*].name'
  EOT
  type = map(object({
    version                          = optional(string)
    override_existing                = optional(bool, false)
    remove_addon_resources_on_delete = optional(bool, true)
    configurations = optional(list(object({
      key   = string
      value = string
    })), [])
    timeouts = optional(object({
      create = optional(string, "30m")
      update = optional(string)
      delete = optional(string)
    }), {})
  }))
  default  = {}
  nullable = false
}

variable "addons_to_remove" {
  description = <<-EOT
    OKE-managed addons to disable, keyed by addon name. Use this to turn off
    add-ons that OKE installs by default (e.g. essential add-ons you want to
    replace). Requires cluster_type = "enhanced" and the OCI CLI on the apply
    host (the removal runs `oci ce cluster disable-addon` via a local-exec).

    Per addon:
      - remove_k8s_resources: also delete the addon's Kubernetes resources.
  EOT
  type = map(object({
    remove_k8s_resources = optional(bool, true)
  }))
  default  = {}
  nullable = false
}

################################################################################
# Managed Node Pools  (maps to eks_managed_node_groups)
################################################################################

variable "node_pools" {
  description = "Managed node pools keyed by name. Maps to eks_managed_node_groups."
  type = map(object({
    compartment_id          = optional(string)
    kubernetes_version      = optional(string)
    shape                   = string
    ocpus                   = optional(number, 2)
    memory                  = optional(number, 16)
    size                    = optional(number, 1)
    autoscale               = optional(bool, false)
    image_id                = optional(string)
    boot_volume_size        = optional(number, 50)
    availability_domains    = optional(list(number))
    placement_fds           = optional(list(string))
    subnet_id               = optional(string)
    nsg_ids                 = optional(list(string), [])
    pod_subnet_id           = optional(string)
    pod_nsg_ids             = optional(list(string), [])
    max_pods_per_node       = optional(number, 31)
    node_labels             = optional(map(string), {})
    node_metadata           = optional(map(string), {})
    volume_kms_key_id       = optional(string)
    pv_transit_encryption   = optional(bool, true)
    capacity_reservation_id = optional(string)
    preemptible_config = optional(object({
      enable                  = optional(bool, false)
      is_preserve_boot_volume = optional(bool, false)
    }), {})
    eviction_grace_duration = optional(number, 300)
    force_node_delete       = optional(bool, false)
    node_cycling = optional(object({
      enabled             = optional(bool, false)
      maximum_surge       = optional(string, "1")
      maximum_unavailable = optional(string, "1")
      cycle_modes         = optional(list(string), ["BOOT_VOLUME_REPLACE"])
    }), {})
    freeform_tags = optional(map(string), {})
    defined_tags  = optional(map(string), {})
  }))
  default  = {}
  nullable = false
}

################################################################################
# Virtual Node Pools  (maps to fargate_profiles)
################################################################################

variable "virtual_node_pools" {
  description = "Virtual (serverless) node pools keyed by name. Requires enhanced cluster + npn CNI. Maps to fargate_profiles."
  type = map(object({
    compartment_id       = optional(string)
    shape                = optional(string, "Pod.Standard.E4.Flex")
    size                 = optional(number, 1)
    availability_domains = optional(list(number))
    subnet_id            = optional(string)
    pod_subnet_id        = optional(string)
    nsg_ids              = optional(list(string), [])
    pod_nsg_ids          = optional(list(string), [])
    node_labels          = optional(map(string), {})
    taints = optional(map(object({
      value  = optional(string)
      effect = optional(string, "NoSchedule")
    })), {})
    freeform_tags = optional(map(string), {})
    defined_tags  = optional(map(string), {})
  }))
  default  = {}
  nullable = false
}

################################################################################
# Self-Managed Node Pools  (maps to self_managed_node_groups)
################################################################################

variable "self_managed_node_pools" {
  description = "Self-managed node pools (instance pools) keyed by name. Maps to self_managed_node_groups."
  type = map(object({
    compartment_id        = optional(string)
    kubernetes_version    = optional(string)
    cloud_init            = optional(string)
    shape                 = string
    ocpus                 = optional(number, 2)
    memory                = optional(number, 16)
    size                  = optional(number, 1)
    autoscale             = optional(bool, false)
    image_id              = optional(string)
    boot_volume_size      = optional(number, 50)
    availability_domains  = optional(list(number))
    placement_fds         = optional(list(string))
    subnet_id             = optional(string)
    nsg_ids               = optional(list(string), [])
    assign_public_ip      = optional(bool, false)
    node_labels           = optional(map(string), {})
    volume_kms_key_id     = optional(string)
    pv_transit_encryption = optional(bool, true)
    node_metadata         = optional(map(string), {})
    freeform_tags         = optional(map(string), {})
    defined_tags          = optional(map(string), {})
  }))
  default  = {}
  nullable = false
}

################################################################################
# Outputs control
################################################################################

variable "enable_sensitive_outputs" {
  description = "Include sensitive detail (kubeconfig, CA cert) in module outputs."
  type        = bool
  default     = false
  nullable    = false
}
