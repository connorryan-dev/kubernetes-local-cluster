# Adding an Application

This guide explains how to onboard an application workload to the cluster using Flux GitOps.

## Pattern

Applications are declaratively managed under the `apps/` directory, reconciled by Flux **after**
the infrastructure layer is ready (thanks to `dependsOn: [infrastructure]` in the `apps.yaml` Kustomization).

Each application should have its own subdirectory with:
- A Flux `GitRepository` (pointing at the app's source repo)
- A Flux `Kustomization` (reconciling a path within that repo)
- Optional: Helm values or overlays if using HelmRelease
- A `kustomization.yaml` aggregating the above

## Quick start: deploying from a GitRepository

Suppose you're deploying the Bento application from a `bento-kubernetes-deployments` repo.

1. Create `apps/bento/`:
   ```bash
   mkdir -p apps/bento
   ```

2. Create a Flux `GitRepository` pointing at the app's deployment repo:
   ```yaml
   # apps/bento/repository.yaml
   apiVersion: source.toolkit.fluxcd.io/v1
   kind: GitRepository
   metadata:
     name: bento-deployments
     namespace: flux-system
   spec:
     interval: 5m
     url: https://github.com/connorryan-dev/bento-kubernetes-deployments.git
     ref:
       branch: main
   ```

3. Create a Flux `Kustomization` to reconcile a path in that repo:
   ```yaml
   # apps/bento/kustomization-resource.yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: bento
     namespace: flux-system
   spec:
     interval: 10m
     sourceRef:
       kind: GitRepository
       name: bento-deployments
     path: ./        # or a more specific path, e.g., ./overlays/kind-desktop
     prune: true
     wait: false
     dependsOn:
       - name: infrastructure  # bento depends on namespaces, operators, etc.
   ```

4. Aggregate both in `apps/bento/kustomization.yaml`:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
     - repository.yaml
     - kustomization-resource.yaml
   ```

5. Reference it from `apps/kustomization.yaml`:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
     - bento/kustomization.yaml
   ```

6. Commit and push:
   ```bash
   git add apps/
   git commit -m "Add Bento application to Flux"
   git push
   ```

7. Verify Flux reconciles it:
   ```bash
   flux get kustomizations | grep bento
   kubectl get pods -n bento-dev  # or whichever namespace Bento uses
   ```

## Alternative: using HelmRelease for Helm-packaged apps

If your app is distributed as a Helm chart:

1. Create a Flux `HelmRepository`:
   ```yaml
   # apps/my-app/helm-repository.yaml
   apiVersion: source.toolkit.fluxcd.io/v1beta2
   kind: HelmRepository
   metadata:
     name: my-app-repo
     namespace: flux-system
   spec:
     interval: 10m
     url: https://charts.example.com/helm
   ```

2. Create a Flux `HelmRelease`:
   ```yaml
   # apps/my-app/helm-release.yaml
   apiVersion: helm.toolkit.fluxcd.io/v2beta2
   kind: HelmRelease
   metadata:
     name: my-app
     namespace: flux-system
   spec:
     interval: 10m
     chart:
       spec:
         chart: my-app
         version: "1.2.x"
         sourceRef:
           kind: HelmRepository
           name: my-app-repo
           namespace: flux-system
     targetNamespace: my-app  # deploy into this namespace
     values:
       # Helm chart values
       image:
         repository: my-app
         tag: latest
   ```

3. Create `apps/my-app/kustomization.yaml`:
   ```yaml
   resources:
     - helm-repository.yaml
     - helm-release.yaml
   ```

## Managing app-specific Secrets

If your app needs encrypted Secrets, store them in the app's directory and enable SOPS:

```yaml
# apps/bento/kustomization.yaml
resources:
  - repository.yaml
  - kustomization-resource.yaml
  - bento-secrets.sops.yaml  # encrypted Secret
```

Then reference SOPS in the `Kustomization`:

```yaml
# apps/bento/kustomization-resource.yaml
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age  # must exist in flux-system
```

See `docs/secrets.md` for how to encrypt and manage secrets.

## CI/CD integration

When you update an app's deployment repo, Flux automatically detects the change (on its sync interval, default ~5–10 minutes) and reconciles.

To trigger an immediate reconcile:
```bash
flux reconcile source git bento-deployments
flux reconcile kustomization bento
```

You can also set up a GitHub webhook in Flux to trigger reconciliation immediately on push (advanced; not configured here yet).

## Namespace and RBAC for apps

If your app needs its own namespace or RBAC roles, add them to the app's directory:

```bash
# apps/my-app/
├── namespace.yaml
├── role.yaml
├── rolebinding.yaml
├── repository.yaml
├── kustomization-resource.yaml
└── kustomization.yaml
```

Then reference them in `kustomization.yaml`:

```yaml
resources:
  - namespace.yaml
  - role.yaml
  - rolebinding.yaml
  - repository.yaml
  - kustomization-resource.yaml
```

## Example: Bento

The `bento-kubernetes-deployments` repo currently has:
- Namespaces: `bento-dev`, `bento-test`
- Postgres, RabbitMQ (via CRD), Redis, OpenBao

When this is migrated to Flux:
1. Create `apps/bento/` with the GitRepository + Kustomization pattern above
2. Ensure the RabbitMQ Cluster Operator is installed in `infrastructure/controllers/` (with its CRD)
3. Declare `dependsOn: [infrastructure]` so RabbitMQ Cluster Operator is ready before Bento reconciles
4. Reference Bento's namespaces and manifests from its own repo

See `apps/README.md` for the current backlog status.

## Troubleshooting

### App Kustomization shows "failed to pull GitRepository"
```bash
flux reconcile source git bento-deployments -n flux-system
flux logs -n flux-system --follow | grep bento
```

Verify the repo URL is correct, the branch exists, and your kubeconfig/RBAC allows access.

### App reconciliation is stuck or not reconciling
```bash
flux get kustomizations | grep my-app
flux describe kustomization my-app -n flux-system
```

Check if the kustomization has a `dependsOn` that isn't ready yet, or if there's a validation error in the manifests.

### Manual validation before pushing
Before committing app manifests, validate them locally:
```bash
kustomize build apps/my-app
kubectl kustomize apps/my-app | kubeconform
```

## Next steps

- See `docs/bootstrap-runbook.md` to set up the cluster from scratch
- See `docs/adding-a-namespace.md` for namespace management
- See `docs/adding-a-controller.md` if your app depends on an operator (e.g., RabbitMQ Cluster Operator)
