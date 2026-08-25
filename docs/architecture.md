# Architecture

This repo uses Flux as a GitOps controller to reconcile Kubernetes cluster state from git.

## Reconciliation graph

```
flux-system (created by `flux bootstrap`)
    ↓
infrastructure.yaml Kustomization
    ├─ namespaces/              (flux-system, github-runners; includes github-runners-quota)
    ├─ sources/                 (empty scaffold — no external sources currently needed)
    └─ controllers/             (scaffold for future operators)
    ↓
apps.yaml Kustomization (dependsOn: infrastructure)
    ├─ openbao/
    ├─ redis/
    └─ github-runners/          (Deployment/ConfigMap/ServiceAccount/RBAC, plain manifests)
        (github-runner-secrets Secret is created manually, not tracked here)
```

## Key concepts

### Namespaces
- `flux-system` — created and managed by `flux bootstrap`, holds Flux controllers and secrets
- `github-runners` — holds the self-hosted GitHub Actions runner pod (Deployment with replicas: 1)

### GitRepository sources
- `flux-system` (auto-created): points to this repo (`kubernetes-local-cluster`) — the only source needed

### Kustomizations (declarative resources)
- `infrastructure`: reconciles `infrastructure/` directory; no `dependsOn` (first to reconcile)
- `apps`: reconciles `apps/` directory (including `apps/github-runners/`); depends on `infrastructure` (apps only start after infra is ready)

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

## Why is the runner image still built in a separate repo?

The GitHub Actions runner's Kubernetes manifests live in this repo (`apps/github-runners/`),
same as any other app — Flux doesn't need a second `GitRepository` for them anymore. The
Docker image itself (Dockerfile, entrypoint.sh) still lives in `github_runners`, since that's
application source code being built, not a Kubernetes manifest — this repo doesn't build
images. `deploy.sh` in that repo builds the image and `kind load docker-image`s it into the
cluster; it no longer touches Kubernetes manifests or Flux.

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
