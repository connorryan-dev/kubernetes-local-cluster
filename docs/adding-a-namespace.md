# Adding a Namespace

This guide explains how to add a new Kubernetes namespace to the cluster and declare it in Flux.

## Quick start

1. Create a new manifest file in `infrastructure/namespaces/`:
   ```yaml
   # infrastructure/namespaces/my-app.yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: my-app
   ```

2. Add it to `infrastructure/namespaces/kustomization.yaml`:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   namespace: default
   resources:
     - github-runners.yaml
     - my-app.yaml          # <- add this line
   ```

3. Commit and push:
   ```bash
   git add infrastructure/namespaces/
   git commit -m "Add my-app namespace"
   git push
   ```

4. Flux will reconcile within ~10 minutes (or trigger manually):
   ```bash
   flux reconcile kustomization infrastructure --with-source
   ```

5. Verify:
   ```bash
   kubectl get ns my-app
   ```

## If your namespace needs a resource Secret or ConfigMap

If your namespace's workloads need shared Secrets or ConfigMaps, you can add them to the namespace kustomization:

```yaml
# infrastructure/namespaces/kustomization.yaml
resources:
  - github-runners.yaml
  - my-app.yaml
  - my-app-secrets.sops.yaml  # encrypted Secret for my-app workloads
```

For secrets, use SOPS encryption (see `docs/secrets.md`).

## Namespace labels and annotations

To add labels or annotations to a namespace (e.g., for pod security policies or monitoring),
use a kustomize patch:

```yaml
# infrastructure/namespaces/kustomization.yaml
resources:
  - my-app.yaml
patchesJson6902:
  - target:
      group: ''
      version: v1
      kind: Namespace
      name: my-app
    patch: |-
      - op: add
        path: /metadata/labels
        value:
          monitoring: enabled
          environment: production
```

## Namespace dependencies

If one namespace must exist before another (e.g., an operator's namespace before the resources it manages),
use Flux Kustomization `dependsOn`:

```yaml
# infrastructure/controllers/my-operator.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: my-operator
  namespace: flux-system
spec:
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./infrastructure/controllers/my-operator
  dependsOn:
    - name: namespaces  # <-- ensures namespaces exist first
```

## Next steps

- See `docs/adding-a-controller.md` if you're installing an operator that requires CRDs
- See `docs/adding-an-app.md` if you're deploying an application workload to this namespace
