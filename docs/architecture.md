# Architecture

This repo uses Flux as a GitOps controller to reconcile Kubernetes cluster state from git.

## Reconciliation graph

```
flux-system (created by `flux bootstrap`)
    ↓
infrastructure.yaml Kustomization
    ├─ namespaces/              (flux-system, github-runners)
    ├─ sources/                 (GitRepository: github_runners repo)
    ├─ controllers/             (scaffold for future operators)
    └─ runners/                 (Flux Kustomization → github_runners' ./helm)
        └─ github-runner-secret.sops.yaml (SOPS-encrypted PAT)
    ↓
apps.yaml Kustomization (dependsOn: infrastructure)
    └─ [empty scaffold for future app workloads]
```

## Key concepts

### Namespaces
- `flux-system` — created and managed by `flux bootstrap`, holds Flux controllers and secrets
- `github-runners` — holds self-hosted GitHub Actions runner pods (Deployment with replicas: 2)

### GitRepository sources
- `flux-system` (auto-created): points to this repo (`kubernetes-local-cluster`)
- `github-runners`: points to the `connorryan-dev/github_runners` repo, Kustomize path `./helm`

### Kustomizations (declarative resources)
- `infrastructure`: reconciles `infrastructure/` directory; no `dependsOn` (first to reconcile)
- `github-runners` (inside `infrastructure/runners/`): reconciles the `github-runners` GitRepository's `./helm` path into `github-runners` namespace, depends on `namespaces` Kustomization
- `apps`: reconciles `apps/` directory; depends on `infrastructure` (apps only start after infra is ready)

### Secrets management
Runner's GitHub PAT (`GITHUB_TOKEN`) is encrypted with SOPS + age and stored in
`infrastructure/runners/github-runner-secret.sops.yaml`. Flux's SOPS Kustomization controller
decrypts it in-cluster using a keypair stored in the `sops-age` Secret (created once per cluster).

See `docs/secrets.md` for setup and rotation.

## Why separate `infrastructure` and `apps`?

Cluster infrastructure (namespaces, CRDs, operators, system workloads) must be ready
before any user applications can safely deploy. The `dependsOn` chain ensures that.

This also keeps the mental model clean: infrastructure is cluster-wide concern; apps
are multi-tenant workloads that depend on infrastructure being stable.

## Why is `github_runners` a separate repo?

The GitHub Actions runner image and Kustomize manifests live in a separate repo
(`github_runners`) for clear separation of concerns:
- Runner repo owns the Docker image, Kustomize manifests, and deployment automation
- This repo owns the cluster-wide orchestration and Flux integration

Flux's `GitRepository` simply points at the runner repo and reconciles its declared state.
If runner code changes, the runner repo is updated, pushed, and Flux picks up the change on its next sync.

## Disaster recovery

If the cluster is recreated (e.g., `kind delete cluster --name=desktop && kind create cluster --name=desktop`),
re-run the bootstrap procedure in `docs/bootstrap-runbook.md`. Flux will restore the entire cluster state from git.

The one exception: the SOPS age keypair (`~/.config/sops/age/keys.txt`) and its corresponding
`sops-age` Secret in `flux-system` must be re-created. This is a documented step in the runbook.
