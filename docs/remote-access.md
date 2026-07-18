# Remote kubectl/k9s Access

The `desktop` KIND cluster runs on the Mac mini (Docker Desktop host). This doc explains why
`kind-config.yaml` (repo root) exists and what breaks if you skip it.

## The problem

By default, `kind create cluster` binds the API server container port to `127.0.0.1` on the
Docker host only, and issues a cert valid for `localhost`/`127.0.0.1`. That's fine if you
only ever run `kubectl` on the Mac mini itself — but this cluster is meant to be driven from
another machine (e.g. a MacBook Pro) over Tailscale, and a loopback-only bind means kubectl
from anywhere else gets `connection refused`, full stop.

This bit the repo once already (July 2026): the cluster had been bootstrapped with a bare
`kind create cluster --name=desktop --image kindest/node:v1.33.0` (no `--config`), and the
existing remote kubeconfig on the MacBook Pro pointed at a stale, unrelated IP left over from
a much older manual setup. Neither pointed at anything reachable. Recreating the cluster with
`kind-config.yaml` fixed it for good.

## The fix: `kind-config.yaml`

```yaml
extraPortMappings:
- containerPort: 6443
  hostPort: 6443
  listenAddress: "0.0.0.0"
  protocol: TCP
```
binds the API server to all interfaces on the Mac mini, and
```yaml
apiServer:
  certSANs:
  - "100.84.198.108"   # Mac mini's Tailscale IP
  - "localhost"
  - "127.0.0.1"
```
adds the Tailscale IP to the server cert so `kubectl` doesn't need
`--insecure-skip-tls-verify`.

Always create/recreate the cluster with this config:
```bash
kind create cluster --name=desktop --image kindest/node:v1.33.0 --config kind-config.yaml
```

Verify it took effect:
```bash
docker ps --filter name=desktop-control-plane --format '{{.Ports}}'
# Expect: 0.0.0.0:6443->6443/tcp   (NOT 127.0.0.1:xxxxx->6443/tcp)
```

## Why Tailscale IP, not a public IP

An older, unrelated local setup (documented in the `bento-kubernetes-deployments` repo's
`REMOTE_ACCESS_SETUP.md`) exposed a different cluster to the public internet — a public IP in
`certSANs`, a router port-forwarding rule, no VPN. That works from anywhere, but it also means
anyone who finds the port can attempt a connection (client cert auth is still required, but
it's still surface area you don't need).

This cluster instead binds to the Mac mini's **Tailscale IP** (`100.84.198.108`). Tailscale
already restricts who can reach that address to devices on the tailnet — no router
configuration, no public exposure, no port-forwarding rule to maintain or forget about.

## Client-side setup (e.g. the MacBook Pro)

1. Fetch the kubeconfig from the Mac mini:
   ```bash
   ssh connor@100.84.198.108 "kind get kubeconfig --name desktop" > kind-remote-config.yaml
   ```
2. Edit the `server:` line to use the Tailscale IP instead of whatever loopback port kind
   printed:
   ```bash
   sed -i '' 's|https://127.0.0.1:[0-9]*|https://100.84.198.108:6443|' kind-remote-config.yaml
   ```
3. Point `KUBECONFIG` at it (session or permanent via shell rc):
   ```bash
   export KUBECONFIG=/path/to/kind-remote-config.yaml
   kubectl get nodes   # should work with no tunnel
   ```

k9s uses the same kubeconfig resolution as kubectl, so it works the same way — no extra
setup once `KUBECONFIG` is pointed correctly.

## What this does NOT cover

- **`docker`/`kind` cluster-lifecycle commands** (create/delete cluster, image builds, `kind
  load docker-image`) still have to run **on the Mac mini** — Docker Desktop only runs there.
  Only `kubectl`/k9s work remotely.
- **Services inside the cluster** (Postgres, Redis, etc. in other projects' namespaces) still
  need their own `kubectl port-forward` — this doc only covers the API server itself.
