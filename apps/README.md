# Applications

## Migrated: OpenBao, Redis, and the GitHub Actions runner

`apps/openbao/` and `apps/redis/` are migrated from the sibling repo
`bento-kubernetes-deployments` (which deployed them imperatively via `kubectl apply` /
`helm install`). Both deploy into the `bento-dev` namespace, matching where they ran
before so Bento's existing connection config (service DNS names, port-forwards) still
works unchanged.

- **OpenBao** — Flux `HelmRepository` + `HelmRelease` (chart `openbao/openbao`), 3-replica
  Raft HA, same minimal dev-cluster resource limits as the source `values.yaml`. Initial
  init/unseal is a manual one-time step — see `apps/openbao/scripts/README.md` and
  `docs/secrets.md`.
- **Redis** — direct port of the source `redis-deployment.yaml` (same image, command,
  resource limits), with the PVC switched to KIND's default `standard` StorageClass
  instead of the source's hardcoded hostPath PV, and the password moved out of git into a
  manually-created Secret (see `docs/secrets.md`).
- **GitHub Actions runner** (`apps/github-runners/`) — migrated from a separate `github_runners`
  GitRepository source into plain manifests in this repo, same pattern as Redis. That sibling
  repo now only holds the Docker image build (Dockerfile, `deploy.sh`); this repo owns the
  Deployment/ConfigMap/ServiceAccount/RBAC and the `github-runners` namespace's ResourceQuota.
  The `GITHUB_TOKEN` Secret is manual — see `docs/secrets.md`.

## Capacitor (Flux UI)

Not deployed in-cluster. Run Capacitor Next locally instead — it uses your kubeconfig and adds
nothing to the cluster:

```bash
brew tap gimlet-io/capacitor && brew install capacitor
capacitor --port 3333   # open http://localhost:3333
```

The legacy in-cluster Capacitor (`ghcr.io/gimlet-io/capacitor-manifests`, final release
`v0.4.8`) was tried and removed: it queries Flux beta APIs that Flux 2.9 no longer serves, so it
shows no events.

## Not migrated

- **Postgres** — already runs outside `bento-kubernetes-deployments`, as a standalone
  container on the NAS. Not part of this repo.
- **RabbitMQ** — removed from the Bento stack entirely upstream; nothing to migrate.

## Future work

A self-host Helm chart packaging Bento + its backing services for external end users has
been discussed as a separate, later effort — it would live in `bentra-runners` (alongside
the existing `charts/bentra-runner` chart), not here. This repo's `apps/` directory is
Flux/GitOps for *this* cluster specifically, not a redistributable installer.

See `docs/adding-an-app.md` for the general how-to guide when onboarding further apps.
