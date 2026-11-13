# Architecture

English | [繁體中文](architecture.zh.md)

Terraform provisions, Argo CD deploys, Rancher manages. A k3s management cluster runs Rancher, cert-manager and Vault; a DOKS workload cluster runs the apps.

![Architecture overview](images/dpl-architecture-overview-en.svg)

The numbers on the overview match the sections below.

## 1. Provisioning · Terraform

![Provisioning](images/dpl-01-provisioning-en.svg)

Terraform creates the infrastructure for both clusters: the Droplet that runs the k3s management cluster, the DOKS workload cluster, the VPC and the DNS records.

## 2. GitOps · Argo CD

![GitOps](images/dpl-02-gitops-en.svg)

Argo CD runs on DOKS and syncs from the infra and apps Git repos. Git is the single source: every app and config on the cluster, including Argo Rollouts, Istio, the OTel Demo and the observability stack, is deployed from there.

## 3. Management · Rancher

![Management](images/dpl-03-management-en.svg)

The Rancher agent (cattle-cluster-agent) on DOKS connects back to Rancher on the management cluster. Rancher provides SSO, RBAC, Projects and a multi-cluster overview. cert-manager issues Rancher's TLS certificates, and rancher-backup takes backups.

## 4. Secrets · Vault

![Secrets](images/dpl-04-secrets-en.svg)

Secrets live in Vault on the management cluster, outside DOKS. External Secrets on DOKS syncs them into the cluster for the apps to use.

## 5. Traffic · Istio + Argo Rollouts

![Traffic](images/dpl-05-traffic-en.svg)

Istio sidecars handle both north-south (incoming) and east-west (service-to-service) routing. Argo Rollouts runs canary releases and header-based routes, and uses Istio to split traffic between the stable and canary versions.

## 6. Observability

![Observability](images/dpl-06-observability-en.svg)

The observability stack collects from the OTel Demo: Prometheus for metrics, Loki for logs, Tempo for traces, and Grafana to view them together.
