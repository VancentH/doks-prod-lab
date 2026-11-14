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
# Prefix length for the admin CIDR. Some ISPs (CGNAT) send different
# connections from different public IPs in the same block, so a /32 can
# block SSH even though curl saw the "right" IP.
# Set ADMIN_CIDR_PREFIX=24 in .envrc on such networks.
ADMIN_CIDR_PREFIX="${ADMIN_CIDR_PREFIX:-32}"

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

# The script connects with BatchMode (no prompts), so a passphrase-protected
# key must already be loaded in ssh-agent.
if ! ssh-keygen -y -P "" -f "$SSH_KEY" >/dev/null 2>&1; then
  key_fp=$(ssh-keygen -lf "${SSH_KEY}.pub" 2>/dev/null | awk '{print $2}')
  ssh-add -l 2>/dev/null | grep -qF "$key_fp" \
    || fail "SSH key $SSH_KEY has a passphrase and is not loaded in ssh-agent. Run: ssh-add --apple-use-keychain $SSH_KEY"
fi

[[ -d "$TF_DIR" ]] || fail "$TF_DIR not found, run this script from the repo root"

ok "Preflight checks passed"

# ---- 2. Detect public IP ----------------------------------------------------
info "Detecting your public IP"
# --noproxy: a proxy would report its own address, not the one SSH uses
my_ip=$(curl -4 -fsS --noproxy '*' --max-time 10 https://api.ipify.org \
        || curl -4 -fsS --noproxy '*' --max-time 10 https://ifconfig.me || true)
[[ "$my_ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || fail "Could not detect a valid public IPv4 address (got: '${my_ip}')"

[[ "$ADMIN_CIDR_PREFIX" =~ ^[0-9]+$ ]] && (( ADMIN_CIDR_PREFIX >= 16 && ADMIN_CIDR_PREFIX <= 32 )) \
  || fail "ADMIN_CIDR_PREFIX must be between 16 and 32 (got: ${ADMIN_CIDR_PREFIX})"

# Network address of my_ip/ADMIN_CIDR_PREFIX, e.g. 203.0.113.10/24 -> 203.0.113.0/24
IFS=. read -r o1 o2 o3 o4 <<< "$my_ip"
ip_int=$(( (o1 << 24) | (o2 << 16) | (o3 << 8) | o4 ))
mask=$(( (0xFFFFFFFF << (32 - ADMIN_CIDR_PREFIX)) & 0xFFFFFFFF ))
net_int=$(( ip_int & mask ))
admin_cidr="$(( (net_int >> 24) & 255 )).$(( (net_int >> 16) & 255 )).$(( (net_int >> 8) & 255 )).$(( net_int & 255 ))/${ADMIN_CIDR_PREFIX}"

export TF_VAR_admin_cidrs="[\"${admin_cidr}\"]"
ok "Detected ${my_ip}; SSH and the k3s API will be allowed from ${admin_cidr}"

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
until ssh_err=$(ssh "${ssh_opts[@]}" "root@${mgmt_ip}" true 2>&1); do
  if (( elapsed >= SSH_TIMEOUT )); then
    warn "Last SSH error: ${ssh_err}"
    case "$ssh_err" in
      *"timed out"*) warn "A timeout usually means the firewall does not allow your real source IP. Try: ADMIN_CIDR_PREFIX=24 ./scripts/up.sh" ;;
      *"Permission denied"*) warn "The key was rejected. Check that ssh_key_name in Terraform matches $SSH_KEY" ;;
    esac
    fail "SSH did not become available within ${SSH_TIMEOUT}s"
  fi
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
