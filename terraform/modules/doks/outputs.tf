output "cluster_id" {
  description = "ID of the DOKS cluster."
  value       = digitalocean_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "Name of the DOKS cluster."
  value       = digitalocean_kubernetes_cluster.this.name
}

output "cluster_urn" {
  description = "URN of the DOKS cluster, used to assign it to a DigitalOcean project."
  value       = digitalocean_kubernetes_cluster.this.urn
}

output "kubernetes_version" {
  description = "Kubernetes version running on the cluster."
  value       = digitalocean_kubernetes_cluster.this.version
}

output "endpoint" {
  description = "Kubernetes API server endpoint."
  value       = digitalocean_kubernetes_cluster.this.endpoint
}

output "vpc_id" {
  description = "ID of the cluster VPC. The management Droplet joins this VPC."
  value       = digitalocean_vpc.this.id
}
