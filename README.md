# doks-prod-lab

Simulates a production-grade environment to practice day-to-day Kubernetes cluster operations.

## Architecture

![Terraform provisions, Argo CD deploys, Rancher manages](docs/images/dpl-architecture-en.svg)

## Stack

- **DigitalOcean Kubernetes (DOKS)**: provisioned via Terraform
- **Terraform**: S3-compatible backend on DigitalOcean Spaces

## Structure

```text
.
|-- README.md
|-- bootstrap
|   `-- rancher.sh            # installs cert-manager + Rancher on the management cluster
|-- docs
|   |-- BRINGUP.md             # scripts/up.sh walkthrough
|   |-- RANCHER.md             # bootstrap/rancher.sh walkthrough, DOKS import
|   |-- TEARDOWN.md            # scripts/down.sh walkthrough
|   `-- VERSIONS.md            # Rancher / cert-manager / DOKS / k3s version matrix
|-- scripts
|   |-- down.sh                # teardown: removes billable resources after a lab session
|   `-- up.sh                  # bring-up: provisions DOKS + management k3s
`-- terraform
    |-- API_TOKEN_SCOPES.md    # required DigitalOcean API token scopes
    |-- envs
    |   `-- lab                 # lab environment (root module)
    |       |-- backend.tf
    |       |-- main.tf
    |       |-- outputs.tf
    |       |-- variables.tf
    |       `-- versions.tf
    `-- modules
        |-- doks                 # reusable DOKS cluster module
        |   |-- main.tf
        |   |-- outputs.tf
        |   |-- variables.tf
        |   `-- versions.tf
        `-- mgmt-k3s              # single-node k3s management cluster module
            |-- cloud-init.yaml.tftpl
            |-- main.tf
            |-- outputs.tf
            `-- variables.tf
```

## Prerequisites

- `terraform` >= 1.6
- `doctl` (authenticated), `kubectl`, `helm`, `jq`, `dig`, `openssl`
- An SSH key already uploaded to the DigitalOcean account (for the management Droplet)
- An existing DigitalOcean DNS zone, created once by hand (for the Rancher hostname)
- Environment variables:
  - `DIGITALOCEAN_TOKEN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (Spaces keys for the Terraform backend)
    - Required API token scopes for `DIGITALOCEAN_TOKEN`: see [terraform/API_TOKEN_SCOPES.md](terraform/API_TOKEN_SCOPES.md)
  - `LETSENCRYPT_EMAIL` (used by `bootstrap/rancher.sh` to request the Rancher certificate)

## Usage

```bash
# bring up DOKS + the management k3s cluster
./scripts/up.sh

# install cert-manager + Rancher, then import DOKS into it (see docs/RANCHER.md)
./bootstrap/rancher.sh

# tear down (deletes billable resources, keeps the Spaces bucket and DNS zone)
./scripts/down.sh
```

See [docs/BRINGUP.md](docs/BRINGUP.md) for the full bring-up walkthrough.

## Guides

- [docs/BRINGUP.md](docs/BRINGUP.md): first bring-up with `scripts/up.sh`, DNS requirements
- [docs/VERSIONS.md](docs/VERSIONS.md): Rancher / cert-manager / DOKS / k3s version matrix
- [docs/RANCHER.md](docs/RANCHER.md): `bootstrap/rancher.sh`, certificate caching, importing DOKS
- [docs/TEARDOWN.md](docs/TEARDOWN.md): `scripts/down.sh`, destroy retries, leftover checks
- [terraform/API_TOKEN_SCOPES.md](terraform/API_TOKEN_SCOPES.md): required DigitalOcean API token scopes
