# OpenBao bootstrap scripts (manual, not Flux-applied)

Copied unchanged from `bento-kubernetes-deployments/openbao/`. These are one-time
imperative steps, not continuously-reconciled state, so Flux doesn't run them — run by
hand after the `openbao` HelmRelease reports `Ready` (all 3 pods `Running`, sealed).

- `init-openbao.sh` — run once after first deploy. Initializes OpenBao (5 key shares / 3
  threshold), writes the root token + unseal keys to the gitignored `unseal-keys.txt` in
  this directory *and* to the `openbao-unseal-keys` Secret in `bento-dev`, then unseals
  all 3 pods. Idempotent — safe to re-run; it's a no-op if already initialized.
- `setup-kubernetes-auth.sh` — optional, deferred. Configures Kubernetes auth + a
  `workflow-runner` role/policy and enables the `bento` KV v2 mount. Not currently used by
  Django (it authenticates with the static root token instead), kept here for parity with
  the source repo in case that changes later.

See `docs/secrets.md` in the repo root for the exact secrets these scripts create.
