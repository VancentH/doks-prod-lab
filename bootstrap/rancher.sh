#!/usr/bin/env bash
# =============================================================================
# rancher.sh — Install cert-manager and Rancher on the k3s management cluster
#
# Location: doks-prod-lab/bootstrap/rancher.sh
# Usage:    run ./bootstrap/rancher.sh from the repo root after scripts/up.sh
#           Safe to re-run: every step uses "helm upgrade --install".
#
# Steps:
#   1. Preflight checks (tools, kubeconfig, DNS)
#   2. Install cert-manager
#   3. Restore the cached Rancher TLS certificate, if still valid
#   4. Install Rancher with a Let's Encrypt certificate
#   5. Wait for the certificate and check https://<hostname>/ping
#   6. Cache the certificate for the next lab session
#
# Why the certificate cache: the lab is rebuilt every session, and Let's
# Encrypt allows only 5 certificates for the same hostname per 7 days.
# Restoring the previous certificate lets cert-manager reuse it instead of
# requesting a new one each time. The cache holds a private key, so it lives
# outside the repo with 0600 permissions.
# =============================================================================
set -euo pipefail

TF_DIR="${TF_DIR:-terraform/envs/lab}"
MGMT_KUBECONFIG="${MGMT_KUBECONFIG:-$HOME/.kube/dpl-mgmt.yaml}"
STATE_DIR="${STATE_DIR:-$HOME/.dpl}"
TLS_CACHE="${TLS_CACHE:-$STATE_DIR/rancher-tls-secret.json}"
PASSWORD_FILE="${PASSWORD_FILE:-$STATE_DIR/rancher-bootstrap-password}"

# Pinned versions. Check compatibility before bumping:
#   cert-manager 1.21 supports Kubernetes 1.33 - 1.36
#   Rancher 2.15.x supports k3s 1.34 - 1.36 and imported clusters 1.34 - 1.36
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.21.0}"
RANCHER_VERSION="${RANCHER_VERSION:-2.15.2}"
RANCHER_CHART_REPO="${RANCHER_CHART_REPO:-rancher-latest}"

# ---- Output helpers ---------------------------------------------------------
info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
fail()  { printf '\033[1;31m[FAIL]\033[0m  %s\n' "$*"; exit 1; }

# ---- 1. Preflight checks ----------------------------------------------------
info "Running preflight checks"

for cmd in kubectl helm terraform dig curl openssl jq; do
  command -v "$cmd" >/dev/null 2>&1 || fail "$cmd not found, please install it first"
done

[[ -f "$MGMT_KUBECONFIG" ]] || fail "$MGMT_KUBECONFIG not found, run ./scripts/up.sh first"
export KUBECONFIG="$MGMT_KUBECONFIG"

[[ -n "${LETSENCRYPT_EMAIL:-}" ]] \
  || fail "LETSENCRYPT_EMAIL is not set (Let's Encrypt sends expiry notices there). Add it to .envrc"

kubectl get nodes >/dev/null 2>&1 \
  || fail "Cannot reach the management cluster. If your IP changed, re-run ./scripts/up.sh"

[[ -d "$TF_DIR" ]] || fail "$TF_DIR not found, run this script from the repo root"
RANCHER_HOSTNAME=$(terraform -chdir="$TF_DIR" output -raw rancher_fqdn)
MGMT_IP=$(terraform -chdir="$TF_DIR" output -raw mgmt_public_ipv4)

# Let's Encrypt validates over HTTP-01, so the public DNS must already point
# at the management Droplet.
resolved_ip=$(dig +short "$RANCHER_HOSTNAME" @1.1.1.1 | tail -n1)
[[ "$resolved_ip" == "$MGMT_IP" ]] \
  || fail "${RANCHER_HOSTNAME} resolves to '${resolved_ip}', expected ${MGMT_IP}. Wait for DNS and retry"

ok "Preflight checks passed (${RANCHER_HOSTNAME} -> ${MGMT_IP})"

# ---- 2. cert-manager --------------------------------------------------------
info "Adding Helm repositories"
# Plain "repo add" (no --force-update) works the same on Helm 3 and Helm 4;
# an "already exists" error is ignored.
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo add "$RANCHER_CHART_REPO" "https://releases.rancher.com/server-charts/${RANCHER_CHART_REPO#rancher-}" >/dev/null 2>&1 || true
helm repo update >/dev/null

helm search repo "${RANCHER_CHART_REPO}/rancher" --version "$RANCHER_VERSION" -o json | jq -e 'length > 0' >/dev/null \
  || fail "Rancher ${RANCHER_VERSION} not found in ${RANCHER_CHART_REPO}. Available: $(helm search repo "${RANCHER_CHART_REPO}/rancher" --versions -o json | jq -r '[.[].version][0:5] | join(", ")')"

info "Installing cert-manager ${CERT_MANAGER_VERSION}"
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version "$CERT_MANAGER_VERSION" \
  --set crds.enabled=true

# Wait with kubectl instead of "helm --wait", whose behaviour changed in Helm 4
for deploy in cert-manager cert-manager-webhook cert-manager-cainjector; do
  kubectl -n cert-manager rollout status "deploy/${deploy}" --timeout=5m
done
ok "cert-manager is ready"

# ---- 3. Restore cached certificate ------------------------------------------
kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if [[ -f "$TLS_CACHE" ]]; then
  # Reuse the cached certificate only if it is valid for at least 7 more days
  if jq -r '.data["tls.crt"]' "$TLS_CACHE" \
      | openssl base64 -d -A \
      | openssl x509 -noout -checkend $((7 * 24 * 3600)) >/dev/null 2>&1; then
    info "Restoring cached Rancher certificate from $TLS_CACHE"
    kubectl apply -f "$TLS_CACHE" >/dev/null
    ok "Cached certificate restored, no new Let's Encrypt request needed"
  else
    warn "Cached certificate expires within 7 days, a new one will be requested"
  fi
else
  info "No cached certificate, a new one will be requested from Let's Encrypt"
fi

# ---- 4. Rancher -------------------------------------------------------------
mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"
if [[ ! -f "$PASSWORD_FILE" ]]; then
  openssl rand -base64 24 | tr -d '/+=' | cut -c1-24 > "$PASSWORD_FILE"
  chmod 600 "$PASSWORD_FILE"
fi
BOOTSTRAP_PASSWORD=$(cat "$PASSWORD_FILE")

info "Installing Rancher ${RANCHER_VERSION} from ${RANCHER_CHART_REPO}"
# - replicas=1: single-node management cluster (lab shortcut)
# - agentTLSMode=system-store: agents trust the Let's Encrypt certificate via
#   the system CA store instead of requiring a pinned private CA
# - letsEncrypt.ingress.class=traefik: k3s ships Traefik as its ingress controller
helm upgrade --install rancher "${RANCHER_CHART_REPO}/rancher" \
  --namespace cattle-system \
  --version "$RANCHER_VERSION" \
  --set hostname="$RANCHER_HOSTNAME" \
  --set bootstrapPassword="$BOOTSTRAP_PASSWORD" \
  --set replicas=1 \
  --set agentTLSMode=system-store \
  --set ingress.tls.source=letsEncrypt \
  --set letsEncrypt.email="$LETSENCRYPT_EMAIL" \
  --set letsEncrypt.ingress.class=traefik

info "Waiting for the Rancher deployment (up to 10 minutes)"
kubectl -n cattle-system rollout status deploy/rancher --timeout=10m
ok "Rancher deployment is ready"

# ---- 5. Certificate and endpoint check --------------------------------------
info "Waiting for the TLS certificate (up to 5 minutes)"
# cert-manager creates the Certificate from the Rancher ingress a few seconds
# after the ingress appears, so wait for it to exist first.
for i in $(seq 1 30); do
  kubectl -n cattle-system get certificate tls-rancher-ingress >/dev/null 2>&1 && break
  (( i == 30 )) && fail "Certificate tls-rancher-ingress was never created, check: kubectl -n cattle-system get ingress,issuer"
  sleep 5
done
kubectl -n cattle-system wait certificate/tls-rancher-ingress \
  --for=condition=Ready --timeout=5m \
  || fail "Certificate not ready, check: kubectl -n cattle-system describe certificate tls-rancher-ingress"
ok "Certificate is ready"

info "Checking https://${RANCHER_HOSTNAME}/ping"
for i in $(seq 1 30); do
  # No -k: the request only succeeds if the certificate is publicly trusted
  if [[ "$(curl -fsS --max-time 5 "https://${RANCHER_HOSTNAME}/ping" 2>/dev/null)" == "pong" ]]; then
    ok "Rancher answers with a trusted certificate"
    break
  fi
  (( i == 30 )) && fail "https://${RANCHER_HOSTNAME}/ping did not answer"
  sleep 10
done

# ---- 6. Cache the certificate -----------------------------------------------
info "Caching the certificate to $TLS_CACHE"
kubectl -n cattle-system get secret tls-rancher-ingress -o json \
  | jq '{apiVersion, kind, type, data,
         metadata: {name: .metadata.name, namespace: .metadata.namespace,
                    annotations: (.metadata.annotations // {})}}' \
  > "$TLS_CACHE"
chmod 600 "$TLS_CACHE"
ok "Certificate cached"

# ---- Summary ----------------------------------------------------------------
echo
ok "Rancher is up"
info "URL:      https://${RANCHER_HOSTNAME}"
info "User:     admin"
info "Password: stored in ${PASSWORD_FILE} (show it with: cat ${PASSWORD_FILE})"
warn "You will be asked to set a new admin password on first login."
