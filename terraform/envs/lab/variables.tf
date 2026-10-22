variable "cluster_name" {
  description = "Name of the DOKS cluster. Must match CLUSTER_NAME used by scripts/down.sh."
  type        = string
  default     = "dpl-cluster"
}

variable "region" {
  description = "DigitalOcean region. The Spaces bucket for state and backups is in the same region."
  type        = string
  default     = "sgp1"
}

variable "kubernetes_version_prefix" {
  description = "Kubernetes minor version to pin."
  type        = string
  default     = "1.37."
}

variable "vpc_ip_range" {
  description = "CIDR for the cluster VPC. Must not overlap with any other VPC in the account (any region) or with the DOKS pod and service ranges."
  type        = string
  default     = "10.110.0.0/20"
}

variable "system_pool_size" {
  description = "Droplet size for the system node pool."
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "system_pool_node_count" {
  description = "Number of nodes in the system node pool."
  type        = number
  default     = 1
}

variable "workload_pool_size" {
  description = "Droplet size for the workload node pool."
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "workload_pool_min_nodes" {
  description = "Minimum number of workload nodes."
  type        = number
  default     = 1
}

variable "workload_pool_max_nodes" {
  description = "Maximum number of workload nodes."
  type        = number
  default     = 3
}
