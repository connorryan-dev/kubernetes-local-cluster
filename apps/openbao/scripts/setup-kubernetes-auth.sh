#!/usr/bin/env bash
# setup-kubernetes-auth.sh
# Automates all steps from openbao/KUBERNETES_AUTH_SETUP.md.
# Run from a pod or host with kubectl access to the cluster.
# OpenBao must be initialized and unsealed before running this.

set -euo pipefail

NAMESPACE="bento-dev"
OPENBAO_POD="openbao-0"
SECRET_NAME="openbao-unseal-keys"

log() { echo "[setup-k8s-auth] $*"; }

# ── Step 0: Read root token ───────────────────────────────────────────────────
log "Reading root token from $SECRET_NAME..."
ROOT_TOKEN=$(kubectl get secret "$SECRET_NAME" \
  -n "$NAMESPACE" \
  -o jsonpath='{.data.root_token}' | base64 -d)

if [ -z "$ROOT_TOKEN" ]; then
  echo "ERROR: root_token not found in $SECRET_NAME secret" >&2
  exit 1
fi

# Helper: run a bao command inside openbao-0 with the root token
bao_exec() {
  kubectl exec "$OPENBAO_POD" -n "$NAMESPACE" -- \
    env BAO_TOKEN="$ROOT_TOKEN" BAO_ADDR="http://127.0.0.1:8200" \
    bao "$@"
}

# Helper: same but with stdin (for heredoc policies)
bao_exec_stdin() {
  kubectl exec -i "$OPENBAO_POD" -n "$NAMESPACE" -- \
    env BAO_TOKEN="$ROOT_TOKEN" BAO_ADDR="http://127.0.0.1:8200" \
    bao "$@"
}

# ── Step 1: TokenReview ServiceAccount + ClusterRoleBinding ──────────────────
log "Step 1: Creating openbao-tokenreview ServiceAccount..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: openbao-tokenreview
  namespace: $NAMESPACE
EOF

log "Creating ClusterRoleBinding for openbao-tokenreview..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: openbao-tokenreview-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: openbao-tokenreview
  namespace: $NAMESPACE
EOF

# ── Step 2: Enable kubernetes auth method ─────────────────────────────────────
log "Step 2: Enabling kubernetes auth method (idempotent)..."
EXISTING_AUTH=$(bao_exec auth list -format=json 2>/dev/null || echo "{}")

if echo "$EXISTING_AUTH" | grep -q '"kubernetes/"'; then
  log "  kubernetes auth already enabled, skipping"
else
  bao_exec auth enable kubernetes
fi

# ── Step 3: Configure auth/kubernetes ─────────────────────────────────────────
log "Step 3: Generating short-lived token for openbao-tokenreview SA..."
REVIEWER_JWT=$(kubectl create token openbao-tokenreview -n "$NAMESPACE" --duration=5m)

log "Configuring auth/kubernetes/config..."
# kubernetes_ca_cert=@ reads the file from inside the pod's own filesystem.
# Every K8s pod has this CA cert mounted automatically.
bao_exec write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc" \
  "kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt" \
  token_reviewer_jwt="$REVIEWER_JWT"

# ── Step 4: Create workflow-runner policy ─────────────────────────────────────
log "Step 4: Writing workflow-runner policy..."
bao_exec_stdin policy write workflow-runner - <<'HCL'
path "bento/data/*" {
  capabilities = ["read"]
}
path "bento/metadata/*" {
  capabilities = ["list"]
}
HCL

# ── Step 5: Create workflow-runner role ───────────────────────────────────────
log "Step 5: Creating auth/kubernetes/role/workflow-runner..."
bao_exec write auth/kubernetes/role/workflow-runner \
  bound_service_account_names="workflow-runner" \
  bound_service_account_namespaces="$NAMESPACE" \
  token_policies="workflow-runner" \
  token_ttl="15m"

# ── Step 6: Enable KV v2 at bento ─────────────────────────────────────────────
log "Step 6: Enabling KV v2 at bento (idempotent)..."
EXISTING_SECRETS=$(bao_exec secrets list -format=json 2>/dev/null || echo "{}")

if echo "$EXISTING_SECRETS" | grep -q '"bento/"'; then
  log "  bento/ KV v2 mount already exists, skipping"
else
  bao_exec secrets enable -path=bento kv-2
fi

log ""
log "Kubernetes auth setup complete."
log "  TokenReview SA:  openbao-tokenreview ($NAMESPACE)"
log "  Auth method:     kubernetes at auth/kubernetes"
log "  Policy:          workflow-runner (read bento/data/*, list bento/metadata/*)"
log "  Role:            workflow-runner -> SA workflow-runner in $NAMESPACE, TTL 15m"
log "  KV mount:        bento (KV v2)"
