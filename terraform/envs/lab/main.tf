# -----------------------------------------------------------------------------
# Provider
# The token is read from the DIGITALOCEAN_TOKEN environment variable.
# Never put it in this file or in a committed .tfvars file.
# -----------------------------------------------------------------------------
provider "digitalocean" {}

locals {
  tags = ["dpl", "env-lab"]
}

# -----------------------------------------------------------------------------
# Workload cluster (DOKS)
# -----------------------------------------------------------------------------
module "doks" {
  source = "../../modules/doks"

  cluster_name              = var.cluster_name
  region                    = var.region
  kubernetes_version_prefix = var.kubernetes_version_prefix
  tags                      = local.tags
  vpc_ip_range              = var.vpc_ip_range
  # module parameters       = lab environment variable values
  system_pool_size        = var.system_pool_size
  system_pool_node_count  = var.system_pool_node_count
  workload_pool_size      = var.workload_pool_size
  workload_pool_min_nodes = var.workload_pool_min_nodes
  workload_pool_max_nodes = var.workload_pool_max_nodes
}

# -----------------------------------------------------------------------------
# Management cluster (single-node k3s on a Droplet, same VPC as DOKS)
# -----------------------------------------------------------------------------
module "mgmt" {
  source = "../../modules/mgmt-k3s"

  name         = var.mgmt_name
  region       = var.region
  vpc_id       = module.doks.vpc_id
  vpc_ip_range = var.vpc_ip_range
  size         = var.mgmt_size
  tags         = local.tags

  ssh_key_name = var.ssh_key_name
  admin_cidrs  = var.admin_cidrs
  k3s_version  = var.k3s_version
  k3s_channel  = var.k3s_channel

  dns_zone         = var.dns_zone
  rancher_hostname = var.rancher_hostname
}

# -----------------------------------------------------------------------------
# DigitalOcean project
# Groups all lab resources so their cost is visible in one place.
# -----------------------------------------------------------------------------
resource "digitalocean_project" "this" {
  name        = "kubernetes-production-guide"
  description = "Production-like Kubernetes lab (DOKS + Rancher)."
  purpose     = "Class project / Educational purposes"
  environment = "Development"

  resources = [
    module.doks.cluster_urn,
    module.mgmt.droplet_urn,
  ]
}
