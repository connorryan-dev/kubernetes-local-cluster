# Managing Secrets (manual)

This repo does **not** manage Kubernetes Secrets through git. Secrets (e.g. the runner's
GitHub PAT) are created directly in the cluster with `kubectl` and are never committed —
encrypted or otherwise.

## Why manual

This repo previously used SOPS + age to keep encrypted Secrets in git, with Flux decrypting
them in-cluster. That's been dropped in favor of a simpler model: nothing secret lives in
this repo, and secrets are applied by hand whenever a cluster is created or recreated.

## Creating the runner's GitHub PAT secret

The `github-runner-secrets` Secret (namespace `github-runners`) supplies `GITHUB_TOKEN` to
the runner Deployment (see `github_runners` repo's `helm/deployment.yaml`). Create it after
the `github-runners` namespace exists:

```bash
kubectl create secret generic github-runner-secrets \
  -n github-runners \
  --from-literal=GITHUB_TOKEN=<your-github-pat>
```

The PAT needs org-level runner registration access (classic PAT with `admin:org` scope, or
a fine-grained PAT with the org's "Self-hosted runners" permission) — the runner registers
via `POST /orgs/{org}/actions/runners/registration-token`, not `repo` scope alone.

## Rotating the PAT

1. Generate a new PAT in GitHub (Settings → Developer settings → Personal access tokens).
2. Re-create the Secret with the new value:
   ```bash
   kubectl create secret generic github-runner-secrets \
     -n github-runners \
     --from-literal=GITHUB_TOKEN=<new-pat> \
     --dry-run=client -o yaml | kubectl apply -f -
   ```
3. Restart the runner pods so they pick up the new token:
   ```bash
   kubectl rollout restart deployment/github-runner -n github-runners
   kubectl get pods -n github-runners --watch
   ```

## After a cluster recreate

A recreated cluster has no Secrets at all — re-run the `kubectl create secret` command
above (and any other manually-managed Secret) after Flux bootstrap finishes. This is a
manual step called out in `docs/bootstrap-runbook.md`'s recreate checklist; nothing in git
restores it for you.

## Adding a new app-specific Secret

Same pattern — create it directly in the target namespace with `kubectl create secret`,
document the exact command in this file or the app's own docs, and never commit the value
anywhere (plaintext or encrypted).
