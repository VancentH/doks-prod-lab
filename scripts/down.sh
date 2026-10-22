#!/usr/bin/env bash
# =============================================================================
# down.sh — Lab-mode teardown script
#
# Purpose: cleanly remove every billable resource after a lab session.
# Location: doks-prod-lab/scripts/down.sh
# Usage:    run ./scripts/down.sh from the repo root
#
# Steps:
#   1. Preflight checks (tools, environment variables)
#   2. Stop Argo CD sync (so it does not recreate deleted resources)
#   3. Delete objects that own resources outside the cluster:
#      LoadBalancer Services, Gateways, PVCs (backed by DO Volumes)
#   4. terraform destroy
#   5. Check for leftover billable resources
#
# Intentionally kept: Spaces bucket (Terraform state, Velero backups)
# =============================================================================
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-dpl-cluster}"
TF_DIR="${TF_DIR:-terraform/envs/lab}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-300}"   # seconds

# ---- Output helpers ---------------------------------------------------------
info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
fail()  { printf '\033[1;31m[FAIL]\033[0m  %s\n' "$*"; exit 1; }

# ---- 1. Preflight checks ----------------------------------------------------
info "Running preflight checks"

for cmd in doctl kubectl terraform; do
  command -v "$cmd" >/dev/null 2>&1 || fail "$cmd not found, please install it first"
done

doctl account get >/dev/null 2>&1 \
  || fail "doctl authentication failed, run: doctl auth switch --context <context>"

[[ -n "${DIGITALOCEAN_TOKEN:-}" ]] \
  || fail "DIGITALOCEAN_TOKEN is not set (required by the Terraform DigitalOcean provider)"

[[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]] \
  || fail "AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY are not set (Spaces keys, required by the Terraform backend)"

[[ -d "$TF_DIR" ]] || fail "$TF_DIR not found, run this script from the repo root"

ok "Preflight checks passed"

# ---- Confirmation -----------------------------------------------------------
echo
warn "This will delete cluster '${CLUSTER_NAME}' and all Terraform-managed resources."
warn "The Spaces bucket will NOT be deleted."
read -r -p "Type the cluster name to confirm: " answer
[[ "$answer" == "$CLUSTER_NAME" ]] || fail "Name does not match, aborting"

# ---- 2 & 3. Clean up objects that create DO resources -----------------------
if doctl kubernetes cluster get "$CLUSTER_NAME" >/dev/null 2>&1; then
  info "Cluster found, fetching kubeconfig"
  doctl kubernetes cluster kubeconfig save "$CLUSTER_NAME" >/dev/null

  # 2. Stop Argo CD, otherwise it re-creates the Services we delete
  if kubectl get ns argocd >/dev/null 2>&1; then
    info "Stopping Argo CD sync"
    kubectl -n argocd scale statefulset argocd-application-controller --replicas=0 >/dev/null 2>&1 || true
    kubectl -n argocd scale deployment argocd-applicationset-controller --replicas=0 >/dev/null 2>&1 || true
    ok "Argo CD stopped"
  fi

  # 3a. Delete LoadBalancer Services (each one is a billable DO Load Balancer)
  lb_svcs=$(kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}')
  if [[ -n "$lb_svcs" ]]; then
    info "Deleting LoadBalancer Services:"
    while IFS=/ read -r ns name; do
      echo "    - $ns/$name"
      kubectl -n "$ns" delete svc "$name" --wait=false
    done <<< "$lb_svcs"
  else
    ok "No LoadBalancer Services"
  fi

  # 3b. Delete Gateways (DOKS Gateway API also provisions Load Balancers)
  if kubectl api-resources --api-group=gateway.networking.k8s.io 2>/dev/null | grep -q '^gateways'; then
    info "Deleting Gateways"
    kubectl delete gateways.gateway.networking.k8s.io -A --all --wait=false >/dev/null 2>&1 || true
  fi

  # 3c. Delete PVCs (with reclaimPolicy=Delete this also removes the DO Volume)
  pvc_count=$(kubectl get pvc -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$pvc_count" -gt 0 ]]; then
    info "Deleting ${pvc_count} PVC(s)"
    kubectl delete pvc -A --all --wait=false
  else
    ok "No PVCs"
  fi

  # Wait until DO has released the Load Balancers and Volumes
  info "Waiting for Load Balancers and Volumes to be released (up to ${WAIT_TIMEOUT}s)"
  elapsed=0
  while (( elapsed < WAIT_TIMEOUT )); do
    lbs=$(doctl compute load-balancer list --no-header --format ID | wc -l | tr -d ' ')
    vols=$(doctl compute volume list --no-header --format ID | wc -l | tr -d ' ')
    if [[ "$lbs" -eq 0 && "$vols" -eq 0 ]]; then
      ok "All Load Balancers and Volumes released"
      break
    fi
    printf '    Remaining LBs: %s, Volumes: %s (%ss)\r' "$lbs" "$vols" "$elapsed"
    sleep 10
    elapsed=$((elapsed + 10))
  done
  echo
  if (( elapsed >= WAIT_TIMEOUT )); then
    warn "Timed out waiting; continuing with terraform destroy (leftovers are checked at the end)"
  fi
else
  warn "Cluster '${CLUSTER_NAME}' not found, skipping in-cluster cleanup"
fi

# ---- 4. terraform destroy ---------------------------------------------------
# DOKS deletes cluster Droplets asynchronously, so the VPC can still have
# members right after the cluster is gone ("Can not delete VPC with members").
# Retry a few times instead of failing on the first attempt.
DESTROY_ATTEMPTS="${DESTROY_ATTEMPTS:-4}"
DESTROY_RETRY_WAIT="${DESTROY_RETRY_WAIT:-60}"   # seconds
destroy_ok=0

for attempt in $(seq 1 "$DESTROY_ATTEMPTS"); do
  info "Running terraform destroy (attempt ${attempt}/${DESTROY_ATTEMPTS})"
  if terraform -chdir="$TF_DIR" destroy -auto-approve; then
    destroy_ok=1
    break
  fi
  if (( attempt < DESTROY_ATTEMPTS )); then
    warn "terraform destroy failed, retrying in ${DESTROY_RETRY_WAIT}s"
    sleep "$DESTROY_RETRY_WAIT"
  fi
done

if [[ "$destroy_ok" -eq 1 ]]; then
  ok "terraform destroy finished"
else
  warn "terraform destroy did not complete, checking leftovers anyway"
fi

# ---- 5. Check for leftover resources ----------------------------------------
info "Checking for leftover billable resources"
leftover=0

check() {
  local label="$1"; shift
  local out
  out=$("$@" 2>/dev/null || true)
  if [[ -n "$out" ]]; then
    warn "Leftover ${label}:"
    echo "$out" | sed 's/^/    /'
    leftover=1
  else
    ok "No ${label}"
  fi
}

check "Kubernetes clusters" doctl kubernetes cluster list --no-header --format Name,Region,Status
check "Droplets"            doctl compute droplet list --no-header --format Name,Region,Status
check "Load Balancers"      doctl compute load-balancer list --no-header --format Name,IP,Status
check "Volumes"             doctl compute volume list --no-header --format Name,Size,Region
check "Snapshots"           doctl compute snapshot list --no-header --format Name,ResourceType,Size
check "Reserved IPs"        doctl compute reserved-ip list --no-header --format IP,Region,DropletName

echo
if [[ "$leftover" -eq 0 ]]; then
  ok "Teardown complete, no billable resources left"
else
  warn "Leftover resources found, review them in the control panel and delete manually"
fi
info "Reminder: check API -> Tokens in the control panel and confirm the doks:${CLUSTER_NAME}... token was removed"

# Non-zero exit code so a failed teardown is never mistaken for a clean one
if [[ "$destroy_ok" -ne 1 || "$leftover" -ne 0 ]]; then
  exit 1
fi
