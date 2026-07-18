# kubernetes-local-cluster

Flux GitOps configuration for a local Kubernetes (KIND) cluster.

This repo holds cluster-wide infrastructure config (namespaces, CRDs, operators) and orchestrates
self-hosted GitHub Actions runners for CI/CD. Applications are managed as GitOps workloads.

## Quick start

To set up a KIND cluster with Flux:

1. Ensure you have `kind`, `kubectl`, `flux`, `gh` installed:
   ```bash
   brew install kind kubernetes-cli fluxcd/tap/flux gh
   ```

2. Create a KIND cluster, bound to the Mac mini's Tailscale IP for remote `kubectl`/`k9s`
   access (see `docs/remote-access.md` for why this matters):
   ```bash
   kind create cluster --name=desktop --image kindest/node:v1.33.0 --config kind-config.yaml
   ```

3. Follow the bootstrap runbook:
   ```bash
   cat docs/bootstrap-runbook.md
   ```

## Repository structure

```
kind-config.yaml           # KIND cluster config: binds API server to the Mac mini's Tailscale IP
clusters/desktop/          # Flux layer Kustomizations for this cluster
infrastructure/            # Cluster-wide infra: namespaces, sources, controllers, runners
  ├── namespaces/          # Namespace definitions
  ├── sources/             # GitRepository objects (where code comes from)
  ├── controllers/         # Operators and cluster controllers (scaffold)
  └── runners/             # GitHub Actions runner deployment (Flux Kustomization only — secrets are manual)
apps/                      # Application workloads (currently a backlog placeholder)
docs/                      # Documentation
  ├── bootstrap-runbook.md # How to set up a cluster from scratch
  ├── architecture.md      # Overview of the reconciliation graph
  ├── secrets.md           # Manual Secret creation/rotation (no secrets live in git)
  ├── remote-access.md     # Why the API server is bound to the Mac mini's Tailscale IP
  ├── adding-a-namespace.md
  ├── adding-a-controller.md
  └── adding-an-app.md
.github/workflows/         # GitHub Actions CI/CD
  ├── validate.yml         # PR validation (lint, dry-run)
  └── reconcile.yml        # Push-to-main reconciliation (self-hosted runners)
```

## Key concepts

- **Flux** (`fluxcd.io`) — declarative GitOps controller; reconciles cluster state from git
- **Manual secrets** — no Secret values ever live in this repo; they're created directly with
  `kubectl create secret` after bootstrap (see `docs/secrets.md`)
- **Self-hosted runners** — GitHub Actions runners deployed on the cluster via Kustomize + Flux
- **Infrastructure-first** — cluster infra (namespaces, CRDs, operators) reconciles before apps

## Documentation

- **Setting up a new cluster?** Start with `docs/bootstrap-runbook.md`
- **Understanding the architecture?** Read `docs/architecture.md`
- **Need remote `kubectl`/k9s access?** See `docs/remote-access.md`
- **Adding a namespace?** See `docs/adding-a-namespace.md`
- **Installing a cluster controller/operator?** See `docs/adding-a-controller.md`
- **Deploying an application?** See `docs/adding-an-app.md`
- **Creating/rotating a Secret?** See `docs/secrets.md`

## Disaster recovery

If the cluster is lost or recreated:

```bash
kind delete cluster --name=desktop
kind create cluster --name=desktop --config kind-config.yaml
# Follow docs/bootstrap-runbook.md
```

Cluster state reconciles back from git via Flux, **except Secrets** — those are never in
git and must be manually re-created after bootstrap (see `docs/secrets.md`).

Note the `--config kind-config.yaml`: this cluster's API server is bound to the Mac mini's
Tailscale IP (not `127.0.0.1`) so `kubectl`/`k9s` work remotely without an SSH tunnel or
port-forward. See `kind-config.yaml` at the repo root and `docs/remote-access.md`.
