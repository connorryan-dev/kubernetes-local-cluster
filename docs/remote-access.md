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
  - "connors-mac-mini.tail93da06.ts.net"   # Mac mini's MagicDNS hostname (stable)
  - "100.123.24.88"                        # Mac mini's current Tailscale IP
  - "localhost"
  - "127.0.0.1"
```
adds the Tailscale names to the server cert so `kubectl` doesn't need
`--insecure-skip-tls-verify`. Clients should target the MagicDNS hostname — Tailscale
IPs are **not stable** across logout/login (see "Tailscale IP churn" below).

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

This cluster instead binds to the Mac mini's **Tailscale address**
(`connors-mac-mini.tail93da06.ts.net`, currently `100.123.24.88`). Tailscale already
restricts who can reach that address to devices on the tailnet — no router configuration,
no public exposure, no port-forwarding rule to maintain or forget about.

## Client-side setup (e.g. the MacBook Pro)

1. Fetch the kubeconfig from the Mac mini:
   ```bash
   ssh connor@connors-mac-mini.tail93da06.ts.net "export PATH=/opt/homebrew/bin:\$PATH && kind get kubeconfig --name desktop" > kind-remote-config.yaml
   ```
2. Edit the `server:` line to use the MagicDNS hostname instead of whatever loopback port
   kind printed:
   ```bash
   sed -i '' 's|https://127.0.0.1:[0-9]*|https://connors-mac-mini.tail93da06.ts.net:6443|' kind-remote-config.yaml
   ```
3. Point `KUBECONFIG` at it (session or permanent via shell rc):
   ```bash
   export KUBECONFIG=/path/to/kind-remote-config.yaml
   kubectl get nodes   # should work with no tunnel
   ```

k9s uses the same kubeconfig resolution as kubectl, so it works the same way — no extra
setup once `KUBECONFIG` is pointed correctly.

## Tailscale IP churn — fix the cert in place, don't recreate

Tailscale IPs change on logout/login (both machines' IPs changed on 2026-07-19, and the
2026-08-07 cluster recreate baked the then-stale IP into the cert, breaking remote kubectl
with `x509: certificate is valid for ..., not <new-ip>`). The kubeconfig `server:` line and
this cluster's `certSANs` are the two places that break. The hostname in `certSANs` makes
clients immune as long as they target the hostname; if the cert itself needs a new SAN,
regenerate it in place — kind nodes are real kubeadm nodes, no cluster recreate needed:

```bash
# On the Mac mini:
docker exec desktop-control-plane sh -c '
  cp /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.crt.bak
  cp /etc/kubernetes/pki/apiserver.key /etc/kubernetes/pki/apiserver.key.bak
  sed -i "s/^  - <OLD_SAN>$/  - <OLD_SAN>\n  - <NEW_SAN>/" /kind/kubeadm.conf
  rm /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
  kubeadm init phase certs apiserver --config /kind/kubeadm.conf   # re-signs from existing CA
'
docker exec desktop-control-plane sh -c 'crictl pods --name kube-apiserver -q | xargs crictl stopp'
```

Then mirror the same `certSANs` edit into the `kube-system/kubeadm-config` ConfigMap and
this repo's `kind-config.yaml`, and clean up the `.bak` files once confirmed. Client creds
stay valid — only the server cert is re-issued.

## What this does NOT cover

- **`docker`/`kind` cluster-lifecycle commands** (create/delete cluster, image builds, `kind
  load docker-image`) still have to run **on the Mac mini** — Docker Desktop only runs there.
  Only `kubectl`/k9s work remotely.
- **Services inside the cluster** (Postgres, Redis, etc. in other projects' namespaces) still
  need their own `kubectl port-forward` — this doc only covers the API server itself.
