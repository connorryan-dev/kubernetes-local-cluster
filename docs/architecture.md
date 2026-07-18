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
        (github-runner-secrets Secret is created manually, not tracked here)
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
No Secret values are tracked in this repo. The runner's GitHub PAT (`GITHUB_TOKEN`, in the
`github-runner-secrets` Secret) is created directly with `kubectl create secret` after
bootstrap — it is not restored by Flux and must be manually re-applied after every cluster
recreate.

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

If the cluster is recreated (e.g., `kind delete cluster --name=desktop && kind create cluster
--name=desktop --config kind-config.yaml`), re-run the bootstrap procedure in
`docs/bootstrap-runbook.md`. Flux will restore the entire cluster state from git.

Two exceptions, both manual, both documented in the runbook:
- **Secrets** — nothing in git; re-create `github-runner-secrets` (and any other Secret) by hand.
- **The runner image** — `github-runner:latest` has no registry and isn't in git either; it
  must be reloaded into the new cluster's containerd via `kind load docker-image` (or
  `github_runners`' `deploy.sh --kind desktop`), even though it still exists in Docker's own
  image store on the host.

See `docs/remote-access.md` for a third gotcha specific to this repo's cluster: recreating
without `kind-config.yaml` silently breaks remote `kubectl`/k9s access.
