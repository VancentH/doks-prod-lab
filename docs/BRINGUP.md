# First Bring-Up

`scripts/up.sh` creates the whole lab: the DOKS workload cluster and the
single-node k3s management cluster. It also sets up local access to both.
Safe to re-run: Terraform only updates the firewall rule for your current IP
and leaves everything else as it is.

## What it does

1. Preflight checks (`doctl`, `kubectl`, `terraform`, SSH key, required env vars).
   The script connects over SSH without prompts, so a passphrase-protected
   key must already be loaded in `ssh-agent`
2. Detects your current public IPv4 (bypassing any HTTP proxy) and exports it
   as `TF_VAR_admin_cidrs`, so SSH (22) and the k3s API (6443) on the
   management Droplet are only open to you. The rule is a `/32` by default;
   see [CGNAT networks](#cgnat-networks) if SSH times out
3. `terraform plan` → confirmation prompt → `terraform apply`
4. Saves the DOKS kubeconfig via `doctl kubernetes cluster kubeconfig save`
5. Waits for SSH and `cloud-init` on the management Droplet, then pulls its
   k3s kubeconfig over SSH into `~/.kube/dpl-mgmt.yaml` (context `dpl-mgmt`)
6. Prints a summary of both clusters' nodes

## CGNAT networks

Some ISPs put customers behind carrier-grade NAT, where different connections
leave from different public IPs in the same block. The IP that `up.sh` detects
may then not be the one SSH uses, and the firewall drops SSH even though the
rule looks right. Widen the rule to the surrounding block:

```bash
ADMIN_CIDR_PREFIX=24 ./scripts/up.sh
```

Or set `export ADMIN_CIDR_PREFIX=24` in `.envrc` on such networks. Accepted
values are 16 – 32. Re-running is safe: Terraform only updates the firewall
rule.

If SSH still doesn't come up, `up.sh` prints the last SSH error with a hint:
a timeout usually means the firewall doesn't allow your real source IP, and
`Permission denied` means the key doesn't match `ssh_key_name` in Terraform.

## DNS

Rancher's hostname is `<rancher_hostname>.<dns_zone>` (see
`terraform/envs/lab/variables.tf`). The DNS zone itself is created once by
hand in the DigitalOcean control panel and is never managed by Terraform.
Only the `A` record for the Rancher hostname is, and it is recreated each
session with a short TTL, since the management Droplet's IP changes every run.

That record must resolve to the management Droplet's public IP **before**
running `bootstrap/rancher.sh` (see [RANCHER.md](RANCHER.md)), since Let's
Encrypt validates the certificate over HTTP-01. `up.sh` prints
`terraform output -raw rancher_fqdn` and the Droplet IP at the end of the run
so you can confirm the record has propagated.

## Using both clusters

```bash
export KUBECONFIG="$HOME/.kube/config:$HOME/.kube/dpl-mgmt.yaml"
kubectl config get-contexts
```

Billing starts as soon as `terraform apply` finishes. Run `./scripts/down.sh`
(see [TEARDOWN.md](TEARDOWN.md)) when you are done with the session.
