# Argo CD Bootstrap

`bootstrap/argocd.sh` installs Argo CD on the DOKS workload cluster and hands
control over to Git. Run it after `./scripts/up.sh` (see
[BRINGUP.md](BRINGUP.md)); it doesn't depend on Rancher and is safe to
re-run.

After this script, nothing else is applied by hand: every platform component
is an Argo CD Application in `platform/apps/`.

## What it does

1. Preflight checks: required tools and an explicit DOKS kubeconfig context,
   so nothing lands on the management cluster by mistake
2. Installs the `argo/argo-cd` Helm chart (pinned, see
   [VERSIONS.md](VERSIONS.md)) with `platform/argocd/values.yaml`, and waits
   for every component with `kubectl rollout status`
3. Applies the AppProjects and the root Application
4. Waits for the `namespaces` Application to become `Synced/Healthy`, then
   prints how to open the UI and the initial admin password

## How Git takes over

```text
root                  platform/argocd/root-app.yaml (applied once by the script)
`-- syncs platform/apps/
    `-- namespaces    platform/apps/namespaces.yaml
        `-- syncs platform/namespaces/  ->  observability, otel-demo
```

The root Application is an "app of apps". To add a platform component, add
an Application manifest to `platform/apps/` and push; the root Application
picks it up. Both Applications sync automatically with `prune` and
`selfHeal`, so anything changed by hand on the cluster is reverted to what is
in Git.

Argo CD reads the `main` branch of `https://github.com/VancentH/doks-prod-lab.git`
over HTTPS. The repo is public, so no credentials are needed, but changes
must be pushed before Argo CD can see them; the script's first sync fails
otherwise. If you fork this repo, change the URL in
`platform/argocd/root-app.yaml`, `platform/argocd/projects.yaml` and
`platform/apps/namespaces.yaml`.

## AppProjects

`platform/argocd/projects.yaml` separates what the platform and the apps may
deploy:

| Project | Source repo | Destinations | Cluster-scoped objects |
| --- | --- | --- | --- |
| `platform` | this repo | any namespace | allowed (CRDs, ClusterRoles, Namespaces) |
| `apps` | the apps repo | `otel-demo` only | none |

Namespaces belong to the platform: the `apps` project deploys into
`otel-demo` but cannot create or delete it.

## Lab settings

`platform/argocd/values.yaml` keeps Argo CD small:

- Every component runs on the system node pool (`node-role.dpl.io/pool: system`)
- Dex (SSO) and notifications are disabled to save memory
- No Ingress or LoadBalancer: the UI is reached through `kubectl port-forward`
- Argo CD is installed by Helm and does not manage itself yet

## Opening the UI

```bash
kubectl --context <doks-context> -n argocd port-forward svc/argocd-server 8080:443
```

Then browse to `https://localhost:8080` (self-signed certificate, accept the
warning) and log in as `admin`. The script prints the exact context and the
initial password from the `argocd-initial-admin-secret` Secret.

## Teardown

`scripts/down.sh` scales the Argo CD controllers to zero before deleting
LoadBalancer Services and PVCs, so Argo CD doesn't recreate them (see
[TEARDOWN.md](TEARDOWN.md)).
