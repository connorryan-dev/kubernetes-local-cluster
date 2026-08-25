# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Flux GitOps configuration for a local Kubernetes (KIND) cluster named `desktop`. There is no
application source code here — every file is a Kubernetes/Flux/Kustomize manifest (YAML) and
docs. No Secret values ever live in this repo (see "Secrets: manual" below). Changes are
validated in CI, then applied to the live cluster by Flux polling this repo on a sync interval
(not by any build/deploy step you run).

## Common commands

Validate manifests locally before pushing (mirrors `.github/workflows/validate.yml`):
```bash
kubectl kustomize infrastructure > /dev/null   # kustomize build for a given tree
kubectl kustomize apps > /dev/null
kubectl kustomize clusters/desktop > /dev/null
kubectl kustomize <dir> | kubeconform -summary -ignore-missing-schemas
yamllint -c "{extends: default, rules: {line-length: disable, comments: disable}}" clusters/ infrastructure/ apps/ .github/workflows/
```

Trigger reconciliation manually instead of waiting for the sync interval:
```bash
flux reconcile source git flux-system --with-source
flux reconcile kustomization infrastructure
flux reconcile kustomization apps
flux get kustomizations --watch
```

Create/rotate the runner's GitHub PAT secret (never committed — see `docs/secrets.md`):
```bash
kubectl create secret generic github-runner-secrets \
  -n github-runners --from-literal=GITHUB_TOKEN=<pat> \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/github-runner -n github-runners
```

Full cluster bootstrap / disaster recovery procedure: `docs/bootstrap-runbook.md`. Short version:
```bash
kind create cluster --name=desktop --image kindest/node:v1.33.0 --config kind-config.yaml
flux bootstrap github --owner=connorryan-dev --repository=kubernetes-local-cluster --branch=main --path=clusters/desktop --personal --context=kind-desktop
# then manually re-create Secrets (docs/secrets.md) — nothing in git restores them
```

There is no test suite, package manager, or build step in this repo — "correctness" means a
manifest that builds cleanly with `kustomize`, passes `kubeconform`, and reconciles `Ready=True`
in Flux.

## Architecture: the reconciliation graph

Flux reconciles top-down from `clusters/desktop/`, which is the path passed to `flux bootstrap`:

```
flux-system (Flux controllers + GitRepository "flux-system", created by `flux bootstrap`)
    ↓
infrastructure.yaml Kustomization  (path: ./infrastructure, no dependsOn — reconciles first)
    ├─ namespaces/     → Kustomization "namespaces" (flux-system, github-runners namespaces;
    │                     includes the github-runners ResourceQuota)
    ├─ sources/        → scaffold, empty (resources: []) — no external GitRepository
    │                     currently needed; add one here if a future app needs it
    └─ controllers/    → scaffold, empty (resources: []) — future operators go here
    ↓
apps.yaml Kustomization  (path: ./apps, dependsOn: [infrastructure])
    ├─ openbao/, redis/ — migrated from bento-kubernetes-deployments (see apps/README.md)
    └─ github-runners/  — Deployment/ConfigMap/ServiceAccount/RBAC for the self-hosted
                           GitHub Actions runner (plain manifests, no external source)
```

Key structural rule: **infrastructure before apps**, enforced via `dependsOn` in the Flux
`Kustomization` objects (not via directory nesting). When adding anything, check whether it
belongs under `infrastructure/` (cluster-wide: namespaces, CRDs, operators, controllers) or
`apps/` (application workloads that assume infrastructure is ready).

Each directory under `infrastructure/` and `apps/` is itself a plain Kustomize `kustomization.yaml`
aggregating raw manifests — separate from the Flux `Kustomization` *custom resources* that point
at these paths from `clusters/desktop/`. Don't conflate the two: a `kind: Kustomization` with
`apiVersion: kustomize.config.k8s.io/v1beta1` is a build-time Kustomize overlay; one with
`apiVersion: kustomize.toolkit.fluxcd.io/v1` is a Flux reconciliation object with `sourceRef`,
`interval`, `dependsOn`, etc.

### The runner's manifests live here; only the image build lives elsewhere

The GitHub Actions self-hosted runner's Kubernetes manifests (`apps/github-runners/`) live in
this repo, same as any other app — no external `GitRepository` needed. Only the Docker image
build (Dockerfile, entrypoint.sh) lives in a sibling repo, `github_runners`, since that's
application source code being built, not a Kubernetes manifest. That repo's `deploy.sh` builds
the image and `kind load docker-image`s it into the cluster; it no longer touches Kubernetes
manifests or Flux. Changing runner *behavior* (replicas, resources, RBAC, env) means editing
`apps/github-runners/` here; changing the runner *image* (installed tools, entrypoint logic)
means editing `github_runners` and re-running its `deploy.sh --kind desktop`.

### Secrets: manual, never in git

No Secret values are tracked in this repo — encrypted or otherwise. The runner's GitHub PAT
(`github-runner-secrets`, namespace `github-runners`) is created directly with `kubectl create
secret` after bootstrap, and must be manually re-created any time the cluster is recreated
(Flux restores everything else from git, but Secrets are the one deliberate exception). Full
workflow, including PAT rotation: `docs/secrets.md`.

### Remote access: `kind-config.yaml`

`kind-config.yaml` (repo root) binds the KIND API server to the Mac mini's Tailscale IP
(`100.84.198.108:6443`) instead of kind's default `127.0.0.1`-only binding, and adds that IP
to the cluster cert's `certSANs`. This is what lets `kubectl`/k9s work from another machine
(e.g. the MacBook Pro) directly, with no SSH tunnel or port-forward for the API server itself.
**Always pass `--config kind-config.yaml` when creating this cluster** — a bare `kind create
cluster` silently regresses to loopback-only and breaks remote access without any visible
error until someone tries to connect from elsewhere. See `docs/remote-access.md` for the full
story (this bit the repo once already, in July 2026). Deliberately scoped to the Tailscale IP
rather than a public IP + router port-forwarding — Tailscale's own auth already gates access
without exposing the API server to the open internet.

### CI (`.github/workflows/`)

- `validate.yml` — runs on PRs touching `clusters/**`, `infrastructure/**`, `apps/**`: kustomize
  build check, kubeconform schema validation, yamllint. This is the gate before merge.
- `reconcile.yml` — runs on push to `main`, on **self-hosted runners** (the very runners this repo
  deploys — `runs-on: [self-hosted, kubernetes, kind]`), and force-triggers `flux reconcile` rather
  than waiting for Flux's poll interval.

## Conventions when extending this repo

- New namespace → `infrastructure/namespaces/<name>.yaml` + add to
  `infrastructure/namespaces/kustomization.yaml` (docs/adding-a-namespace.md)
- New cluster operator/controller → subdirectory under `infrastructure/controllers/` with its own
  `kustomization.yaml`, referenced from `infrastructure/controllers/kustomization.yaml`
  (docs/adding-a-controller.md)
- New application workload → subdirectory under `apps/` with a `GitRepository` + Flux
  `Kustomization` pair, `dependsOn: [infrastructure]` (docs/adding-an-app.md)
- Anything reconciling a path in another repo needs both a `GitRepository` (in `sources/`, or the
  app's own dir) and a Flux `Kustomization` with matching `sourceRef`
