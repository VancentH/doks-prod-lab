# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------
variable "cluster_name" {
  description = "Name of the DOKS cluster. Also used as a prefix for related resources."
  type        = string
}

variable "region" {
  description = "DigitalOcean region slug, e.g. fra1."
  type        = string
}

variable "kubernetes_version_prefix" {
  description = "Kubernetes minor version to pin, e.g. \"1.37.\". The latest patch of this minor is used."
  type        = string
}

variable "tags" {
  description = "Tags applied to the cluster and its node pools."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "vpc_ip_range" {
  description = "CIDR for the cluster VPC. Must be unique across all VPCs in the account."
  type        = string
}

# -----------------------------------------------------------------------------
# System node pool (default pool, runs platform components)
# -----------------------------------------------------------------------------
variable "system_pool_size" {
  description = "Droplet size slug for the system node pool."
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "system_pool_node_count" {
  description = "Number of nodes in the system node pool."
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# Workload node pool (runs application workloads, autoscaled)
# -----------------------------------------------------------------------------
variable "workload_pool_size" {
  description = "Droplet size slug for the workload node pool."
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "workload_pool_min_nodes" {
  description = "Minimum number of nodes in the workload node pool."
  type        = number
  default     = 1
}

variable "workload_pool_max_nodes" {
  description = "Maximum number of nodes in the workload node pool. Caps cost during experiments."
  type        = number
  default     = 3

  validation {
    condition     = var.workload_pool_max_nodes >= var.workload_pool_min_nodes
    error_message = "workload_pool_max_nodes must be greater than or equal to workload_pool_min_nodes."
  }
}

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
variable "destroy_all_associated_resources" {
  description = "Delete Load Balancers, Volumes and Volume snapshots created by the cluster when it is destroyed. Safety net for lab teardown."
  type        = bool
  default     = true
}
