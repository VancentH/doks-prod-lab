# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------
variable "name" {
  description = "Name of the management Droplet. Also used as a prefix for related resources."
  type        = string
}

variable "region" {
  description = "DigitalOcean region. Must match the VPC region."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to join (shared with the DOKS cluster)."
  type        = string
}

variable "vpc_ip_range" {
  description = "CIDR of the VPC. Traffic from this range is allowed in the firewall."
  type        = string
}

variable "tags" {
  description = "Tags applied to the Droplet."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Droplet
# -----------------------------------------------------------------------------
variable "size" {
  description = "Droplet size slug. Rancher needs at least 4 GB of memory."
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "image" {
  description = "Droplet image slug."
  type        = string
  default     = "ubuntu-24-04-x64"
}

variable "ssh_key_name" {
  description = "Name of an SSH key already uploaded to the DigitalOcean account. It is used to log in as root."
  type        = string
}

# -----------------------------------------------------------------------------
# k3s
# -----------------------------------------------------------------------------
variable "k3s_version" {
  description = "Exact k3s version to install, e.g. \"v1.33.5+k3s1\". Pin it to a version supported by the Rancher release you install. Empty means the latest release of k3s_channel."
  type        = string
  default     = ""
}

variable "k3s_channel" {
  description = "k3s release channel, used only when k3s_version is empty."
  type        = string
  default     = "stable"
}

# -----------------------------------------------------------------------------
# Access
# -----------------------------------------------------------------------------
variable "admin_cidrs" {
  description = "CIDRs allowed to reach SSH (22) and the Kubernetes API (6443). Usually your current public IP as /32."
  type        = list(string)

  validation {
    condition     = length(var.admin_cidrs) > 0 && alltrue([for c in var.admin_cidrs : can(cidrhost(c, 0))])
    error_message = "admin_cidrs must contain at least one valid CIDR, e.g. [\"203.0.113.10/32\"]."
  }
}

# -----------------------------------------------------------------------------
# DNS
# -----------------------------------------------------------------------------
variable "dns_zone" {
  description = "Existing DigitalOcean DNS zone, e.g. lab.example.com. It is created once by hand and never managed by this module."
  type        = string
}

variable "rancher_hostname" {
  description = "Record name inside dns_zone for Rancher, e.g. \"rancher\" gives rancher.lab.example.com."
  type        = string
  default     = "rancher"
}

variable "dns_ttl" {
  description = "TTL of the Rancher record in seconds. Short, because the IP changes every lab session."
  type        = number
  default     = 60
}
