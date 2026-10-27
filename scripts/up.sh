#!/usr/bin/env bash
# =============================================================================
# up.sh — Lab-mode bring-up script
#
# Purpose: create the whole lab (DOKS + management k3s) and configure local
#          access to both clusters.
# Location: doks-prod-lab/scripts/up.sh
# Usage:    run ./scripts/up.sh from the repo root
#           Safe to re-run, e.g. after your home IP changed: Terraform only
#           updates the firewall and leaves everything else as it is.
#
# Steps:
#   1. Preflight checks (tools, environment variables)
#   2. Detect your current public IP for the firewall
#   3. terraform plan, confirm, terraform apply
#   4. Save the DOKS kubeconfig
#   5. Wait for k3s on the management Droplet and save its kubeconfig
#   6. Print a summary
# =============================================================================
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-dpl-cluster}"
TF_DIR="${TF_DIR:-terraform/envs/lab}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
MGMT_KUBECONFIG="${MGMT_KUBECONFIG:-$HOME/.kube/dpl-mgmt.yaml}"
MGMT_CONTEXT="${MGMT_CONTEXT:-dpl-mgmt}"
KNOWN_HOSTS="${KNOWN_HOSTS:-$HOME/.ssh/dpl_known_hosts}"
SSH_TIMEOUT="${SSH_TIMEOUT:-300}"   # seconds

# ---- Output helpers ---------------------------------------------------------
info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
fail()  { printf '\033[1;31m[FAIL]\033[0m  %s\n' "$*"; exit 1; }

# ---- 1. Preflight checks ----------------------------------------------------
info "Running preflight checks"

for cmd in doctl kubectl terraform curl ssh ssh-keygen; do
  command -v "$cmd" >/dev/null 2>&1 || fail "$cmd not found, please install it first"
done

doctl account get >/dev/null 2>&1 \
  || fail "doctl authentication failed, run: doctl auth switch --context <context>"

[[ -n "${DIGITALOCEAN_TOKEN:-}" ]] \
  || fail "DIGITALOCEAN_TOKEN is not set (required by the Terraform DigitalOcean provider)"

[[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]] \
  || fail "AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY are not set (Spaces keys, required by the Terraform backend)"

[[ -f "$SSH_KEY" ]] || fail "SSH private key $SSH_KEY not found (set SSH_KEY to override)"

[[ -d "$TF_DIR" ]] || fail "$TF_DIR not found, run this script from the repo root"

ok "Preflight checks passed"

# ---- 2. Detect public IP ----------------------------------------------------
info "Detecting your public IP"
my_ip=$(curl -fsS --max-time 10 https://api.ipify.org || curl -fsS --max-time 10 https://ifconfig.me || true)
[[ "$my_ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || fail "Could not detect a valid public IPv4 address (got: '${my_ip}')"
export TF_VAR_admin_cidrs="[\"${my_ip}/32\"]"
ok "SSH and the k3s API will be allowed from ${my_ip}/32"

# ---- 3. Terraform -----------------------------------------------------------
info "Running terraform plan"
terraform -chdir="$TF_DIR" plan -out=tfplan

echo
read -r -p "Apply this plan? Billing starts once resources are created. [y/N]: " answer
[[ "$answer" =~ ^[Yy]$ ]] || { rm -f "$TF_DIR/tfplan"; fail "Aborted by user, nothing was applied"; }

info "Running terraform apply"
terraform -chdir="$TF_DIR" apply tfplan
rm -f "$TF_DIR/tfplan"
ok "terraform apply finished"

# ---- 4. DOKS kubeconfig -----------------------------------------------------
info "Saving DOKS kubeconfig"
doctl kubernetes cluster kubeconfig save "$CLUSTER_NAME" >/dev/null
ok "DOKS context: $(kubectl config current-context)"

# ---- 5. Management cluster kubeconfig ---------------------------------------
mgmt_ip=$(terraform -chdir="$TF_DIR" output -raw mgmt_public_ipv4)
ssh_opts=(-i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes
          -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS")

# The IP is reused across sessions by different Droplets, so drop any old
# host key for it before connecting.
ssh-keygen -R "$mgmt_ip" -f "$KNOWN_HOSTS" >/dev/null 2>&1 || true

info "Waiting for SSH on ${mgmt_ip} (up to ${SSH_TIMEOUT}s)"
elapsed=0
until ssh "${ssh_opts[@]}" "root@${mgmt_ip}" true 2>/dev/null; do
  (( elapsed >= SSH_TIMEOUT )) && fail "SSH did not become available within ${SSH_TIMEOUT}s"
  sleep 10
  elapsed=$((elapsed + 10))
done
ok "SSH is reachable"

info "Waiting for cloud-init to finish installing k3s"
if ! ssh "${ssh_opts[@]}" "root@${mgmt_ip}" "cloud-init status --wait" >/dev/null; then
  warn "cloud-init reported an error, check: ssh root@${mgmt_ip} 'cat /var/log/cloud-init-output.log'"
fi

info "Fetching k3s kubeconfig"
mkdir -p "$(dirname "$MGMT_KUBECONFIG")"
ssh "${ssh_opts[@]}" "root@${mgmt_ip}" "cat /etc/rancher/k3s/k3s.yaml" \
  | sed -e "s#https://127.0.0.1:6443#https://${mgmt_ip}:6443#" \
        -e "s#: default\$#: ${MGMT_CONTEXT}#" \
  > "$MGMT_KUBECONFIG"
chmod 600 "$MGMT_KUBECONFIG"
ok "Management kubeconfig saved to $MGMT_KUBECONFIG (context: ${MGMT_CONTEXT})"

# ---- 6. Summary -------------------------------------------------------------
echo
info "DOKS nodes:"
kubectl get nodes -L node-role.dpl.io/pool
echo
info "Management nodes:"
kubectl --kubeconfig "$MGMT_KUBECONFIG" get nodes -L node-role.dpl.io/pool

echo
ok "Lab is up"
info "Rancher hostname: $(terraform -chdir="$TF_DIR" output -raw rancher_fqdn) -> ${mgmt_ip}"
info "Use both clusters with: export KUBECONFIG=\$HOME/.kube/config:${MGMT_KUBECONFIG}"
warn "Billing is running. Run ./scripts/down.sh when you are done."
