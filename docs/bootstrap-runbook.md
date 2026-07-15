# Bootstrap Runbook

This is the step-by-step procedure to set up Flux GitOps on a KIND cluster from scratch.

Use this runbook if:
- Setting up a brand-new cluster
- Recovering from a full cluster recreation (e.g., `kind delete cluster --name=desktop && kind create cluster --name=desktop`)

Total time: ~5–10 minutes (depending on image pull times).

## Prerequisites

Ensure these CLIs are installed on your machine:
```bash
kind --version
kubectl --version
flux --version
age --version
sops --version
gh --version
```

If any are missing, install via Homebrew:
```bash
brew install kind kubernetes-cli fluxcd/tap/flux age sops gh
```

## Step 1: Create or verify the KIND cluster

If the cluster already exists:
```bash
kind get clusters
```

If it does NOT exist, or if you need to start fresh:
```bash
kind delete cluster --name=desktop  # if it exists
kind create cluster --name=desktop --image kindest/node:v1.33.0
```

Verify kubeconfig context:
```bash
kubectl config current-context
# Expected output: kind-desktop

kubectl config use-context kind-desktop  # if needed
```

## Step 2: Pre-flight checks

```bash
flux check --pre
```

Expected output: all checks `✔`.

## Step 3: Set up SOPS + age (one-time per machine)

If you have NOT yet generated an age keypair on this machine:
```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
cat ~/.config/sops/age/keys.txt
```

Note the public key from the output (line starting with `age1...`). You'll need it in Step 6.

If you already have the keypair, find the public key:
```bash
grep "age1" ~/.config/sops/age/keys.txt | head -1
```

## Step 4: Create the sops-age Secret in the cluster

This secret allows Flux to decrypt SOPS-encrypted manifests. Create it before bootstrapping:

```bash
kubectl create namespace flux-system
kubectl create secret generic sops-age \
  -n flux-system \
  --from-file=age.agekey=$HOME/.config/sops/age/keys.txt
```

Verify:
```bash
kubectl get secret -n flux-system sops-age
```

## Step 5: Bootstrap Flux

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

## Step 6: Verify Flux is running

```bash
kubectl get pods -n flux-system
flux check
```

Expected output: all Flux controllers (`source-controller`, `kustomize-controller`, `notification-controller`) should be `Running`.

## Step 7: Reconcile once to populate secrets

The runner Secret is encrypted with SOPS and stored in the repo, but Flux needs the encryption key.
Manually trigger a reconciliation to decrypt and apply it:

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

## Step 8: Verify runner pods are running

```bash
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

### Runner pods stuck in Pending
```bash
kubectl describe pod -n github-runners <pod-name>
```

Check if there are resource requests that exceed cluster capacity, or if the image pull is failing.

### SOPS decryption failures
```bash
flux logs --all-namespaces | grep -i sops
```

Ensure the `sops-age` Secret exists and contains the correct age private key.

### Still stuck?
See `docs/secrets.md` for SOPS troubleshooting and `docs/architecture.md` for an overview of the reconciliation flow.

## Cluster recreate checklist

After `kind delete cluster --name=desktop && kind create cluster --name=desktop`, run:

- [ ] Step 1: Verify KIND cluster created
- [ ] Step 2: `flux check --pre`
- [ ] Step 4: Create `sops-age` Secret (assumes age keypair already exists)
- [ ] Step 5: `flux bootstrap github ...`
- [ ] Step 6: `flux check` and verify controllers Running
- [ ] Step 7: Manual reconciliation to decrypt secrets
- [ ] Step 8: Verify runner pods Running
- [ ] Step 9: Verify runner RBAC

Done! The cluster should be fully operational.
