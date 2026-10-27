# Version Alignment

Rancher, cert-manager, DOKS and k3s all have to agree on a Kubernetes minor
version. The lab pins every component to stay inside the range Rancher
2.15.2 supports, rather than tracking the newest release of each tool
independently.

| Component | Pinned version | Supported Kubernetes range | Set in |
| --- | --- | --- | --- |
| Rancher | 2.15.2 | k3s and imported clusters 1.34 – 1.36 | `bootstrap/rancher.sh` (`RANCHER_VERSION`) |
| cert-manager | v1.21.0 | Kubernetes 1.33 – 1.36 | `bootstrap/rancher.sh` (`CERT_MANAGER_VERSION`) |
| DOKS | Kubernetes `1.36.x` | — | `terraform/envs/lab/variables.tf` (`kubernetes_version_prefix`) |
| k3s (management cluster) | `v1.36` channel | — | `terraform/envs/lab/variables.tf` (`k3s_channel`) |

DOKS was originally pinned to `1.37.`, which falls outside Rancher 2.15.2's
supported range for imported clusters (1.34 – 1.36). It was moved down to
`1.36.` so the imported DOKS cluster shows as fully supported instead of
"not verified" in the Rancher UI.

## Bumping a version

Check the new version's supported range in the Rancher and cert-manager
release notes before changing anything, then update both sides together:

- Rancher / cert-manager versions live in `bootstrap/rancher.sh`
- DOKS / k3s versions live in `terraform/envs/lab/variables.tf`

A mismatch does not necessarily break the lab immediately, but Rancher will
flag the imported DOKS cluster as unsupported and future Rancher/cert-manager
upgrades may start rejecting it outright.
