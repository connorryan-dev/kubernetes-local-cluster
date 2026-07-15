# Adding a Cluster Controller or Operator

This guide explains how to add a new Kubernetes operator or controller (e.g., RabbitMQ Cluster Operator, cert-manager, KEDA)
to the cluster using Flux.

## Quick start (Helm-based operator)

Most modern operators are distributed via Helm. Example: RabbitMQ Cluster Operator.

1. Create a directory for the operator:
   ```bash
   mkdir -p infrastructure/controllers/rabbitmq-cluster-operator
   ```

2. Create a Flux `HelmRepository` (if not already in `infrastructure/sources/`):
   ```yaml
   # infrastructure/sources/rabbitmq-repository.yaml
   apiVersion: source.toolkit.fluxcd.io/v1beta2
   kind: HelmRepository
   metadata:
     name: rabbitmq
     namespace: flux-system
   spec:
     interval: 10m
     url: https://charts.bitnami.com/bitnami
   ```

3. Add it to `infrastructure/sources/kustomization.yaml`:
   ```yaml
   resources:
     - github-runners-repo.yaml
     - rabbitmq-repository.yaml  # <- add this
   ```

4. Create a Flux `HelmRelease` for the operator:
   ```yaml
   # infrastructure/controllers/rabbitmq-cluster-operator/release.yaml
   apiVersion: helm.toolkit.fluxcd.io/v2beta2
   kind: HelmRelease
   metadata:
     name: rabbitmq-cluster-operator
     namespace: flux-system
   spec:
     interval: 10m
     chart:
       spec:
         chart: rabbitmq-cluster-operator
         version: "3.13.x"  # use a version constraint
         sourceRef:
           kind: HelmRepository
           name: rabbitmq
           namespace: flux-system
     install:
       crds: create
     upgrade:
       crds: createReplace
     values:
       # operator-specific values here
       # see the Helm chart documentation
   ```

5. Create `infrastructure/controllers/rabbitmq-cluster-operator/kustomization.yaml`:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
     - release.yaml
   ```

6. Add it to `infrastructure/controllers/kustomization.yaml`:
   ```yaml
   resources:
     - rabbitmq-cluster-operator/kustomization.yaml
   ```

7. Commit and push:
   ```bash
   git add infrastructure/
   git commit -m "Add RabbitMQ Cluster Operator via Helm"
   git push
   ```

8. Flux will reconcile within ~10 minutes. Verify:
   ```bash
   flux get helmreleases -n flux-system
   kubectl get crds | grep rabbitmq
   ```

## Raw Kubernetes manifests (no Helm)

If the operator is distributed as raw YAML (no Helm chart), clone/fork its repo and reference it:

```yaml
# infrastructure/sources/my-operator-repo.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: my-operator
  namespace: flux-system
spec:
  interval: 10m
  url: https://github.com/example-org/my-operator.git
  ref:
    branch: main
    # or use semver: ">=0.1.0"
```

Then create a Kustomization pointing at the operator's manifest path:

```yaml
# infrastructure/controllers/my-operator/kustomization.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: my-operator
  namespace: flux-system
spec:
  sourceRef:
    kind: GitRepository
    name: my-operator
  path: ./config/manager  # path in the operator repo
```

## Managing operator namespaces

If the operator needs its own namespace (often true for system operators), create it first:

```yaml
# infrastructure/namespaces/my-operator.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-operator
```

Then update the Kustomization to reference this namespace and depend on the namespaces Kustomization:

```yaml
# infrastructure/controllers/my-operator/kustomization.yaml (if using HelmRelease)
apiVersion: helm.toolkit.fluxcd.io/v2beta2
kind: HelmRelease
metadata:
  name: my-operator
  namespace: flux-system
spec:
  # ... values omitted
  targetNamespace: my-operator  # operator pod runs in this namespace
  dependsOn:
    - name: namespaces  # ensure namespace exists first
```

## Reconciliation dependencies

If workloads depend on the operator being ready (e.g., Bento depending on RabbitMQ Cluster Operator),
declare this in the app Kustomization:

```yaml
# apps/bento/kustomization.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: bento
  namespace: flux-system
spec:
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./apps/bento
  dependsOn:
    - name: infrastructure  # wait for infrastructure (including operators) to be ready
```

This ensures Bento's RabbitMQ `RabbitmqCluster` CRD usage doesn't proceed until the operator exists.

## Example: RabbitMQ from bento-kubernetes-deployments

The sibling repo `bento-kubernetes-deployments` contains raw manifests for a `RabbitmqCluster`:

```yaml
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: rabbitmq
  namespace: bento-dev
spec:
  # cluster configuration
```

This CRD is managed by the RabbitMQ Cluster Operator. Once the operator is installed via the
pattern above, the CRD manifests can be onboarded as part of the Bento app (see `apps/README.md`).

## Troubleshooting

### HelmRelease shows "failed to fetch Helm repository"
```bash
flux reconcile source helm rabbitmq -n flux-system
flux logs -n flux-system --follow | grep rabbitmq
```

Verify the Helm repository URL is correct and accessible.

### Operator pods are CrashLoopBackOff
```bash
kubectl logs -n <operator-namespace> <operator-pod>
kubectl describe pod -n <operator-namespace> <operator-pod>
```

Check resource constraints, missing RBAC, or misconfigured values.

### CRDs not installed
Some Helm charts require `install.crds: create` and `upgrade.crds: createReplace` in the HelmRelease
to manage CRDs lifecycle. See the example above.

## Next steps

- See `docs/adding-a-namespace.md` to create a namespace for the operator or its workloads
- See `docs/adding-an-app.md` if you're onboarding an application that uses this operator
