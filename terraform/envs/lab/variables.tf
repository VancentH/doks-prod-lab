# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------
variable "region" {
  description = "DigitalOcean region for the clusters and the VPC."
  type        = string
  default     = "sgp1"
}

variable "vpc_ip_range" {
  description = "CIDR for the shared VPC. Must not overlap with any other VPC in the account (any region) or with the DOKS pod and service ranges."
  type        = string
  default     = "10.110.0.0/20"
}

# -----------------------------------------------------------------------------
# Workload cluster (DOKS)
# -----------------------------------------------------------------------------
variable "cluster_name" {
  description = "Name of the DOKS cluster. Must match CLUSTER_NAME used by scripts/up.sh and scripts/down.sh."
  type        = string
  default     = "dpl-cluster"
}

variable "kubernetes_version_prefix" {
  description = "Kubernetes minor version to pin. Keep within the range supported by the Rancher release in use."
  type        = string
  default     = "1.36."
}

variable "k3s_channel" {
  description = "k3s release channel. Pin to a minor version supported by Rancher, e.g. v1.36."
  type        = string
  default     = "v1.36"
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

# -----------------------------------------------------------------------------
# Management cluster (k3s)
# -----------------------------------------------------------------------------
variable "mgmt_name" {
  description = "Name of the management Droplet."
  type        = string
  default     = "dpl-mgmt"
}

variable "mgmt_size" {
  description = "Droplet size for the management cluster. Rancher needs at least 4 GB of memory."
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "k3s_version" {
  description = "Exact k3s version. Empty installs the latest stable release; pin it before installing Rancher."
  type        = string
  default     = ""
}

variable "ssh_key_name" {
  description = "Name of an SSH key already in your DigitalOcean account. Check with: doctl compute ssh-key list"
  type        = string
  default     = "dpl-key"
}

variable "admin_cidrs" {
  description = "CIDRs allowed to reach SSH and the k3s API. No default: scripts/up.sh sets TF_VAR_admin_cidrs from your current public IP. Never commit your IP."
  type        = list(string)
}

# -----------------------------------------------------------------------------
# DNS
# -----------------------------------------------------------------------------
variable "dns_zone" {
  description = "Existing DigitalOcean DNS zone, created once by hand. Replace the example value with your own zone."
  type        = string
  default     = "lab.example.com"
}

variable "rancher_hostname" {
  description = "Record name inside dns_zone for Rancher."
  type        = string
  default     = "rancher"
}
