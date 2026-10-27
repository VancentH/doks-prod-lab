# Rancher Bootstrap

`bootstrap/rancher.sh` installs cert-manager and Rancher on the k3s
management cluster, then imports the DOKS workload cluster so both are
managed from one place. Run it after `./scripts/up.sh` (see
[BRINGUP.md](BRINGUP.md)); it is safe to re-run since every step uses
`helm upgrade --install`.

See [VERSIONS.md](VERSIONS.md) for why these particular versions are pinned.

## What it does

1. Preflight checks: required tools, management kubeconfig, and that the
   Rancher DNS record already resolves to the management Droplet (it won't
   if `up.sh` just finished and DNS hasn't propagated yet)
2. Installs cert-manager and waits for its three Deployments to be ready
3. Restores a cached Rancher TLS certificate, if one exists and is valid for
   at least 7 more days
4. Installs Rancher with `ingress.tls.source=letsEncrypt`, a single replica,
   and `agentTLSMode=system-store` (agents trust the public CA instead of a
   pinned private one)
5. Waits for the `tls-rancher-ingress` Certificate to become ready and checks
   `https://<rancher-hostname>/ping` without `-k`, so the check only passes
   on a certificate a real browser would also trust
6. Caches the certificate for the next session

## Certificate caching

The lab is torn down and rebuilt every session, and Let's Encrypt allows only
5 certificates per hostname per 7 days. Without caching, a couple of
rebuild/teardown cycles in a week would hit that limit and leave Rancher
without a valid certificate.

The cached certificate Secret is written to `~/.dpl/rancher-tls-secret.json`
with `0600` permissions, **outside the repo**, since it contains a private
key. `rancher.sh` restores it before installing Rancher, so cert-manager
reuses the existing certificate instead of requesting a new one.

## Helm 4 compatibility

The script avoids two behaviors that changed between Helm 3 and Helm 4:

- `helm repo add` is used without `--force-update`; an "already exists"
  error on a second run is ignored instead of relying on flag behavior that
  differs between versions
- Readiness is checked with `kubectl rollout status` instead of `helm
  --wait`, whose semantics changed in Helm 4

## Importing DOKS into Rancher

DOKS has no Rancher-hosted provider the way EKS/AKS/GKE do, so the workload
cluster is imported manually as a **Registered cluster**:

1. In the Rancher UI, go to **Cluster Management → Import Existing**
2. Follow the generated `kubectl apply` command against the DOKS kubeconfig
   (the one `up.sh` already saved)
3. The DOKS `cattle-cluster-agent` connects back to Rancher over HTTPS (port
   443 on the management Droplet, open to the internet for exactly this
   reason; see the firewall rules in
   `terraform/modules/mgmt-k3s/main.tf`)

Once the agent connects, both the imported DOKS cluster and the management
cluster itself (`local`) show **Active** in Rancher's cluster list. Rancher
only manages access, RBAC, Projects and the multi-cluster view from here on.
The cluster's lifecycle (create/upgrade/destroy) stays with Terraform and
`doctl`, not Rancher.
