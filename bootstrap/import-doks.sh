#!/usr/bin/env bash
# =============================================================================
# import-doks.sh — Register the DOKS cluster in Rancher through the Rancher API
#
# Location: doks-prod-lab/bootstrap/import-doks.sh
# Usage:    run ./bootstrap/import-doks.sh from the repo root after
#           ./bootstrap/rancher.sh. Safe to re-run: an existing import is reused.
#
# Steps:
#   1. Preflight checks (tools, kubeconfig contexts, Rancher reachable)
#   2. Log in to Rancher and get an API token
#   3. Make sure the Rancher server URL is set (agents connect back to it)
#   4. Create the imported cluster (same call the "Import Existing > Generic"
#      button makes)
#   5. Apply the registration manifest to DOKS
#   6. Wait until Rancher reports the cluster as Ready
# =============================================================================
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-dpl-cluster}"
RANCHER_CLUSTER_NAME="${RANCHER_CLUSTER_NAME:-$CLUSTER_NAME}"
TF_DIR="${TF_DIR:-terraform/envs/lab}"
STATE_DIR="${STATE_DIR:-$HOME/.dpl}"
PASSWORD_FILE="${PASSWORD_FILE:-$STATE_DIR/rancher-bootstrap-password}"
READY_TIMEOUT="${READY_TIMEOUT:-600}"   # seconds

# ---- Output helpers ---------------------------------------------------------
info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
fail()  { printf '\033[1;31m[FAIL]\033[0m  %s\n' "$*"; exit 1; }

# ---- 1. Preflight checks ----------------------------------------------------
info "Running preflight checks"

for cmd in kubectl terraform curl jq doctl; do
  command -v "$cmd" >/dev/null 2>&1 || fail "$cmd not found, please install it first"
done

[[ -d "$TF_DIR" ]] || fail "$TF_DIR not found, run this script from the repo root"
RANCHER_HOSTNAME=$(terraform -chdir="$TF_DIR" output -raw rancher_fqdn)
RANCHER_URL="https://${RANCHER_HOSTNAME}"

# Admin password: RANCHER_PASSWORD wins (set it if you already changed the
# password in the UI), otherwise the bootstrap password from rancher.sh.
if [[ -z "${RANCHER_PASSWORD:-}" ]]; then
  [[ -f "$PASSWORD_FILE" ]] || fail "$PASSWORD_FILE not found and RANCHER_PASSWORD is not set, run ./bootstrap/rancher.sh first"
  RANCHER_PASSWORD=$(cat "$PASSWORD_FILE")
fi

# Use an explicit DOKS context so the manifest can never land on the
# management cluster by mistake.
doctl kubernetes cluster kubeconfig save "$CLUSTER_NAME" >/dev/null
DOKS_CONTEXT=$(kubectl config get-contexts -o name | grep -E "^do-[a-z0-9]+-${CLUSTER_NAME}\$" | head -n1 || true)
[[ -n "$DOKS_CONTEXT" ]] || fail "No kubeconfig context found for DOKS cluster '${CLUSTER_NAME}'"
kubectl --context "$DOKS_CONTEXT" get nodes >/dev/null 2>&1 \
  || fail "Cannot reach DOKS through context ${DOKS_CONTEXT}"

[[ "$(curl -fsS --max-time 10 "${RANCHER_URL}/ping" 2>/dev/null)" == "pong" ]] \
  || fail "${RANCHER_URL}/ping does not answer, run ./bootstrap/rancher.sh first"

ok "Preflight checks passed (DOKS context: ${DOKS_CONTEXT})"

# ---- 2. Log in --------------------------------------------------------------
info "Logging in to Rancher as admin"
login_body=$(jq -n --arg p "$RANCHER_PASSWORD" \
  '{username: "admin", password: $p, responseType: "token", description: "import-doks.sh"}')
RANCHER_TOKEN=$(curl -fsS -X POST "${RANCHER_URL}/v3-public/localProviders/local?action=login" \
  -H "Content-Type: application/json" -d "$login_body" | jq -r '.token // empty') \
  || true
[[ -n "$RANCHER_TOKEN" ]] \
  || fail "Login failed. If you changed the admin password in the UI, run: RANCHER_PASSWORD='<new password>' $0"
ok "Logged in"

# Small wrapper so every call is authenticated and fails loudly
api() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -fsS -X "$method" "${RANCHER_URL}${path}" \
      -H "Authorization: Bearer ${RANCHER_TOKEN}" -H "Content-Type: application/json" -d "$body"
  else
    curl -fsS -X "$method" "${RANCHER_URL}${path}" -H "Authorization: Bearer ${RANCHER_TOKEN}"
  fi
}

# ---- 3. Server URL ----------------------------------------------------------
# The registration manifest points agents at this URL. It is normally set on
# the first UI login, so set it here when the UI has not been opened yet.
current_url=$(api GET /v3/settings/server-url | jq -r '.value // empty')
if [[ "$current_url" != "$RANCHER_URL" ]]; then
  info "Setting Rancher server URL to ${RANCHER_URL}"
  api PUT /v3/settings/server-url "$(jq -n --arg v "$RANCHER_URL" '{value: $v}')" >/dev/null
fi
ok "Server URL: ${RANCHER_URL}"

# ---- 4. Create the imported cluster ----------------------------------------
cluster_path="/v1/provisioning.cattle.io.clusters/fleet-default/${RANCHER_CLUSTER_NAME}"
if api GET "$cluster_path" >/dev/null 2>&1; then
  info "Cluster '${RANCHER_CLUSTER_NAME}' already exists in Rancher, reusing it"
else
  info "Creating imported cluster '${RANCHER_CLUSTER_NAME}'"
  api POST /v1/provisioning.cattle.io.clusters "$(jq -n --arg n "$RANCHER_CLUSTER_NAME" \
    '{type: "provisioning.cattle.io.cluster", metadata: {name: $n, namespace: "fleet-default"}, spec: {}}')" >/dev/null
fi

# Rancher assigns an internal ID (c-xxxxx) shortly after creation
info "Waiting for Rancher to assign a cluster ID"
for i in $(seq 1 30); do
  CLUSTER_ID=$(api GET "$cluster_path" | jq -r '.status.clusterName // empty')
  [[ -n "$CLUSTER_ID" ]] && break
  (( i == 30 )) && fail "Rancher did not assign a cluster ID"
  sleep 2
done
ok "Cluster ID: ${CLUSTER_ID}"

# ---- 5. Apply the registration manifest ------------------------------------
info "Fetching the registration manifest URL"
for i in $(seq 1 30); do
  MANIFEST_URL=$(api GET "/v3/clusterregistrationtokens?clusterId=${CLUSTER_ID}" \
    | jq -r '[.data[] | select(.manifestUrl != null and .manifestUrl != "")][0].manifestUrl // empty')
  [[ -n "$MANIFEST_URL" ]] && break
  (( i == 30 )) && fail "No registration token was created for ${CLUSTER_ID}"
  sleep 2
done

info "Applying the registration manifest to DOKS"
# No --insecure: the Let's Encrypt certificate is publicly trusted
curl -fsS "$MANIFEST_URL" | kubectl --context "$DOKS_CONTEXT" apply -f - >/dev/null
ok "Manifest applied"

info "Waiting for cattle-cluster-agent on DOKS"
kubectl --context "$DOKS_CONTEXT" -n cattle-system rollout status deploy/cattle-cluster-agent --timeout=5m

# ---- 6. Wait for Ready ------------------------------------------------------
info "Waiting for Rancher to report the cluster as active (up to ${READY_TIMEOUT}s)"
elapsed=0
# Use the management cluster state (what the UI shows as "Active"). The
# provisioning object's Ready condition is not always set for imported clusters.
while :; do
  state=$(api GET "/v3/clusters/${CLUSTER_ID}" | jq -r '.state // "unknown"')
  [[ "$state" == "active" ]] && break
  (( elapsed >= READY_TIMEOUT )) && fail "Cluster is not active after ${READY_TIMEOUT}s (last state: ${state}). Check the Rancher UI"
  printf '    state: %s (%ss)\r' "$state" "$elapsed"
  sleep 10
  elapsed=$((elapsed + 10))
done
echo

echo
ok "DOKS is registered in Rancher as '${RANCHER_CLUSTER_NAME}' (${CLUSTER_ID})"
info "Open: ${RANCHER_URL}/dashboard/c/${CLUSTER_ID}/explorer"
