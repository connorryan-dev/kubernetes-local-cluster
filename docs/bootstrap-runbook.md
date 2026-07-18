# Bootstrap Runbook

This is the step-by-step procedure to set up Flux GitOps on a KIND cluster from scratch.

Use this runbook if:
- Setting up a brand-new cluster
- Recovering from a full cluster recreation (e.g., `kind delete cluster --name=desktop && kind create cluster --name=desktop --config kind-config.yaml`)

Total time: ~5–10 minutes (depending on image pull times).

## Prerequisites

Ensure these CLIs are installed on your machine:
```bash
kind --version
kubectl --version
flux --version
gh --version
```

If any are missing, install via Homebrew:
```bash
brew install kind kubernetes-cli fluxcd/tap/flux gh
```

## Step 1: Create or verify the KIND cluster

If the cluster already exists:
```bash
kind get clusters
```

If it does NOT exist, or if you need to start fresh, create it with `kind-config.yaml`
(repo root) — this binds the API server to the Mac mini's Tailscale IP instead of kind's
default `127.0.0.1`-only binding, so `kubectl`/k9s work remotely without a tunnel. See
`docs/remote-access.md` for why this matters; a bare `kind create cluster` with no
`--config` will silently break remote access.

```bash
kind delete cluster --name=desktop  # if it exists
kind create cluster --name=desktop --image kindest/node:v1.33.0 --config kind-config.yaml
```

Verify kubeconfig context and remote binding:
```bash
kubectl config current-context
# Expected output: kind-desktop

kubectl config use-context kind-desktop  # if needed

docker ps --filter name=desktop-control-plane --format '{{.Ports}}'
# Expected output includes: 0.0.0.0:6443->6443/tcp
```

## Step 2: Pre-flight checks

```bash
flux check --pre
```

Expected output: all checks `✔`.

## Step 3: Bootstrap Flux

```bash
kubectl config use-context kind-desktop
export GITHUB_TOKEN=$(gh auth token)
flux bootstrap github \
  --owner=connorryan-dev \
  --repository=kubernetes-local-cluster \
  --branch=main \
  --path=clusters/desktop \
  --personal \
  --context=kind-desktop
```

This command:
- Creates the `flux-system` namespace (if not already done) and applies Flux controllers
- Creates a `GitRepository` pointing at `kubernetes-local-cluster`
- Creates a `Kustomization` pointing at `clusters/desktop`
- Pushes a deploy key to the GitHub repo (read-only, used for pulling updates)

Wait for the command to complete. Expected output: `✔ all components are healthy`.

## Step 4: Verify Flux is running

```bash
kubectl get pods -n flux-system
flux check
```

Expected output: all Flux controllers (`source-controller`, `kustomize-controller`, `notification-controller`) should be `Running`.

## Step 5: Reconcile once

Trigger an immediate reconciliation rather than waiting for the poll interval:

```bash
flux reconcile kustomization flux-system --with-source
```

Then wait for the infrastructure to be ready:
```bash
flux get kustomizations --watch
```

Expected output (after ~1–2 minutes):
```
NAME              READY STATUS
flux-system       True  Applied revision main@sha1:...
infrastructure    True  Applied revision main@sha1:...
```

## Step 6: Load the runner image into the cluster

The runner image (`github-runner:latest`) is custom-built and has no registry — it must be
loaded directly into the cluster's nodes. This is **not tracked by Flux** and must be redone
after every cluster recreate (the node's containerd image cache is wiped, even though the
image still exists in Docker's own image store on the Mac mini). From the `github_runners`
repo:

```bash
./deploy.sh --skip-push --skip-deploy --kind desktop
```

Or manually, if the image is already built:
```bash
kind load docker-image github-runner:latest --name desktop
```

## Step 7: Create the runner's GitHub PAT secret

No Secret values live in git (see `docs/secrets.md`). Create it manually:

```bash
kubectl create secret generic github-runner-secrets \
  -n github-runners \
  --from-literal=GITHUB_TOKEN=<your-github-pat>
```

The PAT needs org-level runner registration access (classic PAT with `admin:org` scope) —
the runner registers via `POST /orgs/{org}/actions/runners/registration-token`.

## Step 8: Verify runner pods are running

```bash
kubectl rollout restart deployment/github-runner -n github-runners
kubectl get pods -n github-runners
```

Expected output:
```
NAME                        READY   STATUS    RESTARTS   AGE
github-runner-...           2/2     Running   0          ...
github-runner-...           2/2     Running   0          ...
```

Each pod should show `2/2 Running` (runner container + dind sidecar).

## Step 9: Verify runner RBAC

```bash
kubectl get clusterrolebinding github-runner-cluster-admin
```

Expected output: a `ClusterRoleBinding` binding the runner ServiceAccount to the `cluster-admin` role.

## Troubleshooting

### Flux components not running
```bash
kubectl get pods -n flux-system
kubectl describe pod -n flux-system <pod-name>
```

Check for image pull errors, disk pressure, or resource constraints.

### Runner pods stuck in `ImagePullBackOff`
The image wasn't loaded into the (new) cluster's containerd — see Step 6. Confirm with:
```bash
kubectl describe pod -n github-runners <pod-name>   # look for "Pulling image"/"Failed to pull image"
ssh <mac-mini> "docker images | grep github-runner"  # confirm the image exists on the host at all
```

### Runner pods `CreateContainerConfigError` or crash-looping on startup
The `github-runner-secrets` Secret is missing or the PAT is invalid/expired. Check:
```bash
kubectl get secret github-runner-secrets -n github-runners   # NotFound? → Step 7
kubectl logs -n github-runners <pod-name> -c runner            # "Failed to obtain registration token" → PAT invalid/expired, rotate it (docs/secrets.md)
```

### Runner pods stuck in Pending
```bash
kubectl describe pod -n github-runners <pod-name>
```

Check if there are resource requests that exceed cluster capacity.

### Still stuck?
See `docs/architecture.md` for an overview of the reconciliation flow.

## Cluster recreate checklist

After `kind delete cluster --name=desktop && kind create cluster --name=desktop --config kind-config.yaml`, run:

- [ ] Step 1: Verify KIND cluster created (with `kind-config.yaml` — check `docker ps` shows `0.0.0.0:6443`)
- [ ] Step 2: `flux check --pre`
- [ ] Step 3: `flux bootstrap github ...`
- [ ] Step 4: `flux check` and verify controllers Running
- [ ] Step 5: Manual reconciliation
- [ ] Step 6: Load the runner image (`deploy.sh --kind desktop` from `github_runners` repo)
- [ ] Step 7: Manually re-create `github-runner-secrets` (docs/secrets.md — nothing in git restores this)
- [ ] Step 8: Verify runner pods Running
- [ ] Step 9: Verify runner RBAC

Done! The cluster should be fully operational.
