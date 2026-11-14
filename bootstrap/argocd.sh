#!/usr/bin/env bash
# =============================================================================
# argocd.sh — Install Argo CD on DOKS and hand control over to Git
#
# Location: doks-prod-lab/bootstrap/argocd.sh
# Usage:    run ./bootstrap/argocd.sh from the repo root after scripts/up.sh
#           Safe to re-run.
#
# Steps:
#   1. Preflight checks (tools, DOKS context)
#   2. Install Argo CD with Helm (system node pool)
#   3. Apply the AppProjects and the root Application
#   4. Wait for the first Application to sync and print login details
#
# The repo is public, so Argo CD reads it over HTTPS without credentials.
# After this script, everything else is deployed by Argo CD from Git.
# =============================================================================
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-dpl-cluster}"

# Pinned chart version. Check the Argo CD release notes before bumping.
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-10.7.0}"

# ---- Output helpers ---------------------------------------------------------
info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
fail()  { printf '\033[1;31m[FAIL]\033[0m  %s\n' "$*"; exit 1; }

# ---- 1. Preflight checks ----------------------------------------------------
info "Running preflight checks"

for cmd in kubectl helm jq doctl openssl; do
  command -v "$cmd" >/dev/null 2>&1 || fail "$cmd not found, please install it first"
done

[[ -f platform/argocd/values.yaml ]] || fail "Run this script from the repo root"

# Explicit DOKS context so nothing lands on the management cluster
doctl kubernetes cluster kubeconfig save "$CLUSTER_NAME" >/dev/null
DOKS_CONTEXT=$(kubectl config get-contexts -o name | grep -E "^do-[a-z0-9]+-${CLUSTER_NAME}\$" | head -n1 || true)
[[ -n "$DOKS_CONTEXT" ]] || fail "No kubeconfig context found for DOKS cluster '${CLUSTER_NAME}'"
k() { kubectl --context "$DOKS_CONTEXT" "$@"; }
k get nodes >/dev/null 2>&1 || fail "Cannot reach DOKS through context ${DOKS_CONTEXT}"

ok "Preflight checks passed (DOKS context: ${DOKS_CONTEXT})"

# ---- 2. Install Argo CD -----------------------------------------------------
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null

helm search repo argo/argo-cd --version "$ARGOCD_CHART_VERSION" -o json | jq -e 'length > 0' >/dev/null \
  || fail "argo-cd chart ${ARGOCD_CHART_VERSION} not found. Available: $(helm search repo argo/argo-cd --versions -o json | jq -r '[.[].version][0:5] | join(", ")')"

info "Installing Argo CD (chart ${ARGOCD_CHART_VERSION})"
helm upgrade --install argocd argo/argo-cd \
  --kube-context "$DOKS_CONTEXT" \
  --namespace argocd --create-namespace \
  --version "$ARGOCD_CHART_VERSION" \
  -f platform/argocd/values.yaml

# Wait with kubectl instead of "helm --wait", whose behaviour changed in Helm 4
for deploy in argocd-server argocd-repo-server argocd-redis argocd-applicationset-controller; do
  k -n argocd rollout status "deploy/${deploy}" --timeout=5m
done
k -n argocd rollout status statefulset/argocd-application-controller --timeout=5m
ok "Argo CD is running"

# ---- 3. AppProjects and root Application ------------------------------------
info "Applying AppProjects and the root Application"
k apply -f platform/argocd/projects.yaml >/dev/null
k apply -f platform/argocd/root-app.yaml >/dev/null
ok "Git is now the source of truth"

# ---- 4. Wait for the first sync ---------------------------------------------
info "Waiting for the 'namespaces' Application to sync (up to 5 minutes)"
for i in $(seq 1 30); do
  status=$(k -n argocd get application namespaces -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)
  [[ "$status" == "Synced/Healthy" ]] && break
  if (( i == 30 )); then
    k -n argocd get applications 2>/dev/null || true
    fail "Application 'namespaces' is not Synced/Healthy (last: '${status}'). If the root app shows a repo error, check that the repo is pushed"
  fi
  sleep 10
done
ok "Application 'namespaces' is Synced/Healthy"
k get namespace observability otel-demo

# ---- Summary ----------------------------------------------------------------
password=$(k -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | openssl base64 -d -A)
echo
ok "Argo CD is up"
info "Open the UI:  kubectl --context ${DOKS_CONTEXT} -n argocd port-forward svc/argocd-server 8080:443"
info "Then browse:  https://localhost:8080  (self-signed certificate, accept the warning)"
info "User:         admin"
info "Password:     ${password}"
