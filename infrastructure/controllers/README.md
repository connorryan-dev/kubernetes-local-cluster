# Cluster Controllers and Operators

This directory holds scaffold and manifests for cluster-wide Kubernetes controllers and operators
(e.g., RabbitMQ Cluster Operator, cert-manager, KEDA, etc.).

## Pattern

For each controller, create a subdirectory with:
- `namespace.yaml` (if the operator needs its own namespace)
- A Flux `HelmRelease` (for Helm-based operators) or raw CRD manifests
- A Flux `HelmRepository` or `GitRepository` (if needed)
- A `kustomization.yaml` aggregating the above

Reference the controller in `infrastructure/controllers/kustomization.yaml` so Flux reconciles it.

## Dependencies

The `infrastructure.yaml` Kustomization (at `clusters/desktop/infrastructure.yaml`)
ensures this controller scaffold is reconciled _before_ the `apps` Kustomization,
so any CRDs or namespaces a controller provides are available to user workloads.

## Example: RabbitMQ Cluster Operator

The `bento-kubernetes-deployments` repo (sibling repo) contains a worked example of
a RabbitMQ `RabbitmqCluster` CRD usage. When Bento's Kubernetes deployment is migrated
into this repo (tracked in `apps/README.md` backlog), the RabbitMQ Cluster Operator
should be installed here and structured as described above.

## Current state

This directory is scaffold-only — no operators are currently installed.
