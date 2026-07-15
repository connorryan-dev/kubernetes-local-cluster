# Applications (Backlog)

This directory is reserved for application-specific workloads deployed to the cluster.
It is currently empty — Flux's `apps` Kustomization has `resources: []`.

## Future work: Migrate Bento

The sibling repo `bento-kubernetes-deployments` contains the current imperative deployment
configuration for the Bento application, including:
- Namespaces: `bento-dev`, `bento-test`
- Postgres, RabbitMQ, Redis (backing services)
- OpenBao (secrets management)

This is a candidate for the first "real" app to migrate into this repo using Flux GitOps.

### Recommended approach (when ready)

1. Create `apps/bento/` subdirectory
2. Convert raw manifests and Helm values to Flux `HelmRelease` + `GitRepository`/`HelmRepository` sources
3. Ensure RabbitMQ Cluster Operator and other required CRDs are installed in `infrastructure/controllers/`
4. Add a Flux `Kustomization` in `infrastructure/runners/kustomization.yaml` with `dependsOn: [infrastructure]`
   so Bento does not reconcile until infrastructure is ready
5. Update the CI workflow in `.github/workflows/` to validate Bento-specific manifests

### Documentation

See `docs/adding-an-app.md` for the how-to guide.
