# doks-prod-lab

Simulates a production-grade environment to practice day-to-day Kubernetes cluster operations.

## Stack

- **DigitalOcean Kubernetes (DOKS)**: provisioned via Terraform
- **Terraform**: S3-compatible backend on DigitalOcean Spaces

## Structure

```text
terraform/
  envs/lab/       # lab environment (root module)
  modules/doks/    # reusable DOKS cluster module
scripts/
  down.sh          # teardown: removes billable resources after a lab session
```

## Prerequisites

- `terraform` >= 1.6
- `doctl` (authenticated)
- `kubectl`
- Environment variables: `DIGITALOCEAN_TOKEN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (Spaces keys for the Terraform backend)

## Usage

```bash
# provision
terraform -chdir=terraform/envs/lab init
terraform -chdir=terraform/envs/lab apply

# tear down (deletes billable resources, keeps the Spaces bucket)
./scripts/down.sh
```
