locals {
  rancher_fqdn = "${var.rancher_hostname}.${var.dns_zone}"

  # Pin an exact version when given, otherwise follow the release channel
  k3s_install_env = (
    var.k3s_version != ""
    ? "INSTALL_K3S_VERSION=${var.k3s_version}"
    : "INSTALL_K3S_CHANNEL=${var.k3s_channel}"
  )
}

# -----------------------------------------------------------------------------
# SSH key
# The key is a persistent account resource, uploaded once by hand (like the
# Spaces bucket and the DNS zone). DigitalOcean rejects uploading the same key
# twice, so it is only looked up here, never created or deleted.
# -----------------------------------------------------------------------------
data "digitalocean_ssh_key" "admin" {
  name = var.ssh_key_name
}

# -----------------------------------------------------------------------------
# Management Droplet (single-node k3s)
# Lab shortcut: production would run a 3-node HA cluster, because Rancher and
# Vault going down affects every downstream cluster.
# -----------------------------------------------------------------------------
resource "digitalocean_droplet" "this" {
  name     = var.name
  region   = var.region
  size     = var.size
  image    = var.image
  vpc_uuid = var.vpc_id
  ssh_keys = [data.digitalocean_ssh_key.admin.id]
  tags     = var.tags

  monitoring = true
  ipv6       = false

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    rancher_fqdn    = local.rancher_fqdn
    k3s_install_env = local.k3s_install_env
  })
}

# -----------------------------------------------------------------------------
# Cloud Firewall
# - SSH and the Kubernetes API only from the admin IP(s)
# - HTTP/HTTPS from anywhere: Rancher UI, Let's Encrypt HTTP-01 challenges and
#   the cattle-cluster-agent connecting back from DOKS
# - Anything from inside the VPC
# -----------------------------------------------------------------------------
resource "digitalocean_firewall" "this" {
  name        = "${var.name}-fw"
  droplet_ids = [digitalocean_droplet.this.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.admin_cidrs
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "6443"
    source_addresses = var.admin_cidrs
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "1-65535"
    source_addresses = [var.vpc_ip_range]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "1-65535"
    source_addresses = [var.vpc_ip_range]
  }

  inbound_rule {
    protocol         = "icmp"
    source_addresses = [var.vpc_ip_range]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# -----------------------------------------------------------------------------
# DNS record for Rancher
# The zone itself is persistent and created by hand; only the record lives
# and dies with the lab, so no dangling record is left after teardown.
# -----------------------------------------------------------------------------
data "digitalocean_domain" "zone" {
  name = var.dns_zone
}

resource "digitalocean_record" "rancher" {
  domain = data.digitalocean_domain.zone.id
  type   = "A"
  name   = var.rancher_hostname
  value  = digitalocean_droplet.this.ipv4_address
  ttl    = var.dns_ttl
}
