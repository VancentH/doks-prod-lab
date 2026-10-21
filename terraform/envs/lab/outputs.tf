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
