output "cluster_name" {
  description = "Name of the DOKS cluster."
  value       = module.doks.cluster_name
}

output "cluster_id" {
  description = "ID of the DOKS cluster."
  value       = module.doks.cluster_id
}

output "kubernetes_version" {
  description = "Kubernetes version running on the cluster."
  value       = module.doks.kubernetes_version
}

output "vpc_id" {
  description = "ID of the cluster VPC."
  value       = module.doks.vpc_id
}

output "kubeconfig_command" {
  description = "Command to add this cluster to your local kubeconfig."
  value       = "doctl kubernetes cluster kubeconfig save ${module.doks.cluster_name}"
}

# -----------------------------------------------------------------------------
# Management cluster (k3s)
# -----------------------------------------------------------------------------
output "mgmt_public_ipv4" {
  description = "Public IPv4 address of the management Droplet."
  value       = module.mgmt.public_ipv4
}

output "mgmt_private_ipv4" {
  description = "Private IPv4 address of the management Droplet."
  value       = module.mgmt.private_ipv4
}

output "rancher_fqdn" {
  description = "Domain name for Rancher."
  value       = module.mgmt.rancher_fqdn
}

output "mgmt_ssh_command" {
  description = "Command to SSH into the management Droplet."
  value       = "ssh root@${module.mgmt.public_ipv4}"
}
