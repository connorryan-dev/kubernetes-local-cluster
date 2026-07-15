# kubernetes-local-cluster

Flux GitOps configuration for a local Kubernetes (KIND) cluster.

This repo holds cluster-wide infrastructure config (namespaces, CRDs, operators) and orchestrates
self-hosted GitHub Actions runners for CI/CD. Applications are managed as GitOps workloads.

## Quick start

To set up a KIND cluster with Flux:

1. Ensure you have `kind`, `kubectl`, `flux`, `age`, `sops` installed:
   ```bash
   brew install kind kubernetes-cli fluxcd/tap/flux age sops gh
   ```

2. Create a KIND cluster:
   ```bash
   kind create cluster --name=desktop --image kindest/node:v1.33.0
   ```

3. Follow the bootstrap runbook:
   ```bash
   cat docs/bootstrap-runbook.md
   ```

## Repository structure

```
clusters/desktop/          # Flux layer Kustomizations for this cluster
infrastructure/            # Cluster-wide infra: namespaces, sources, controllers, runners
  ├── namespaces/          # Namespace definitions
  ├── sources/             # GitRepository objects (where code comes from)
  ├── controllers/         # Operators and cluster controllers (scaffold)
  └── runners/             # GitHub Actions runner deployment + SOPS-encrypted secrets
apps/                      # Application workloads (currently a backlog placeholder)
docs/                      # Documentation
  ├── bootstrap-runbook.md # How to set up a cluster from scratch
  ├── architecture.md      # Overview of the reconciliation graph
  ├── secrets.md           # SOPS + age setup and management
  ├── adding-a-namespace.md
  ├── adding-a-controller.md
  └── adding-an-app.md
.github/workflows/         # GitHub Actions CI/CD
  ├── validate.yml         # PR validation (lint, dry-run)
  └── reconcile.yml        # Push-to-main reconciliation (self-hosted runners)
```

## Key concepts

- **Flux** (`fluxcd.io`) — declarative GitOps controller; reconciles cluster state from git
- **SOPS + age** — encrypts Secrets in git; Flux decrypts them in-cluster
- **Self-hosted runners** — GitHub Actions runners deployed on the cluster via Kustomize + Flux
- **Infrastructure-first** — cluster infra (namespaces, CRDs, operators) reconciles before apps

## Documentation

- **Setting up a new cluster?** Start with `docs/bootstrap-runbook.md`
- **Understanding the architecture?** Read `docs/architecture.md`
- **Adding a namespace?** See `docs/adding-a-namespace.md`
- **Installing a cluster controller/operator?** See `docs/adding-a-controller.md`
- **Deploying an application?** See `docs/adding-an-app.md`
- **Managing secrets?** See `docs/secrets.md`

## Disaster recovery

If the cluster is lost or recreated:

```bash
kind delete cluster --name=desktop
kind create cluster --name=desktop --image kindest/node:v1.33.0
# Follow docs/bootstrap-runbook.md
```

The entire cluster state is restored from git (minus the SOPS age keypair, which is documented as a manual step).
