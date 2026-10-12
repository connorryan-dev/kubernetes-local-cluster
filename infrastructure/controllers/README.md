# Cluster Controllers and Operators

This directory holds scaffold and manifests for cluster-wide Kubernetes controllers and operators
(e.g., KEDA, cert-manager).

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

See `docs/adding-a-controller.md` for a worked example (KEDA).

## Current state

This directory is scaffold-only — no operators are currently installed.
