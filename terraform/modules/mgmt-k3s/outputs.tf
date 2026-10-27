output "droplet_id" {
  description = "ID of the management Droplet."
  value       = digitalocean_droplet.this.id
}

output "droplet_urn" {
  description = "URN of the management Droplet, used to assign it to a DigitalOcean project."
  value       = digitalocean_droplet.this.urn
}

output "public_ipv4" {
  description = "Public IPv4 address of the management Droplet."
  value       = digitalocean_droplet.this.ipv4_address
}

output "private_ipv4" {
  description = "Private (VPC) IPv4 address of the management Droplet."
  value       = digitalocean_droplet.this.ipv4_address_private
}

output "rancher_fqdn" {
  description = "Fully qualified domain name for Rancher."
  value       = local.rancher_fqdn
}
