# -----------------------------------------------------------------------------
# Kubernetes version
# Pin the minor version and take the latest available patch, so the cluster
# is reproducible across lab sessions without hard-coding a patch release.
# -----------------------------------------------------------------------------
data "digitalocean_kubernetes_versions" "this" {
  version_prefix = var.kubernetes_version_prefix
}

# -----------------------------------------------------------------------------
# VPC
# A dedicated VPC keeps the cluster and the management Droplet on one private
# network, separate from anything else in the account.
# -----------------------------------------------------------------------------
resource "digitalocean_vpc" "this" {
  name     = "${var.cluster_name}-vpc"
  region   = var.region
  ip_range = var.vpc_ip_range
}

# -----------------------------------------------------------------------------
# DOKS cluster
# The inline node_pool is the default pool. It is used as the "system" pool
# for platform components (Argo CD, Istio, observability).
# -----------------------------------------------------------------------------
resource "digitalocean_kubernetes_cluster" "this" {
  name     = var.cluster_name
  region   = var.region
  version  = data.digitalocean_kubernetes_versions.this.latest_version
  vpc_uuid = digitalocean_vpc.this.id
  tags     = var.tags

  # Lab settings: no HA control plane (extra cost), no automatic upgrades
  # (upgrades are practised manually as part of Part 2).
  ha            = false
  auto_upgrade  = false
  surge_upgrade = true

  # Remove LBs, Volumes and snapshots together with the cluster.
  destroy_all_associated_resources = var.destroy_all_associated_resources

  node_pool {
    name       = "system"
    size       = var.system_pool_size
    node_count = var.system_pool_node_count
    tags       = var.tags

    labels = {
      "node-role.dpl.io/pool" = "system"
    }
  }

  maintenance_policy {
    day        = "sunday"
    start_time = "04:00"
  }
}

# -----------------------------------------------------------------------------
# Workload node pool
# Autoscaled within a small range so experiments (load tests, canaries) cannot
# grow the bill without limit.
# -----------------------------------------------------------------------------
resource "digitalocean_kubernetes_node_pool" "workload" {
  cluster_id = digitalocean_kubernetes_cluster.this.id
  name       = "workload"
  size       = var.workload_pool_size
  tags       = var.tags

  auto_scale = true
  min_nodes  = var.workload_pool_min_nodes
  max_nodes  = var.workload_pool_max_nodes

  labels = {
    "node-role.dpl.io/pool" = "workload"
  }
}
