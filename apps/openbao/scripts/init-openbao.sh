#!/usr/bin/env bash
# init-openbao.sh
# Run once after a fresh OpenBao deployment to initialize the cluster,
# store unseal keys in a Kubernetes Secret and locally, then unseal all pods.
#
# Usage:
#   ./init-openbao.sh
#
# Prerequisites:
#   - kubectl configured for the target cluster
#   - OpenBao deployed via Helm (3 replicas, bento-dev namespace)
#   - openbao-0 pod must be Running before you run this script

set -euo pipefail

NAMESPACE="bento-dev"
SECRET_NAME="openbao-unseal-keys"
OUTPUT_FILE="$(dirname "$0")/unseal-keys.txt"
KEY_SHARES=5
KEY_THRESHOLD=3
PODS=(openbao-0 openbao-1 openbao-2)

# ── helpers ──────────────────────────────────────────────────────────────────

log() { echo "[init-openbao] $*"; }

wait_for_pod() {
    local pod="$1"
    log "Waiting for $pod to be Running..."
    kubectl wait pod "$pod" \
        -n "$NAMESPACE" \
        --for=condition=Ready \
        --timeout=120s 2>/dev/null || true

    # Even if not Ready (sealed pods aren't Ready), wait for Running phase
    for i in $(seq 1 30); do
        PHASE=$(kubectl get pod "$pod" -n "$NAMESPACE" \
            -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$PHASE" = "Running" ]; then
            log "$pod is Running"
            return 0
        fi
        log "  $pod phase: ${PHASE:-pending} (attempt $i/30)..."
        sleep 5
    done
    echo "ERROR: $pod did not reach Running phase in time" >&2
    exit 1
}

bao_exec() {
    local pod="$1"; shift
    kubectl exec "$pod" -n "$NAMESPACE" -- bao "$@"
}

# ── main ─────────────────────────────────────────────────────────────────────

log "Step 1: Waiting for openbao-0..."
wait_for_pod openbao-0

# Allow OpenBao time to fully start its listener
sleep 5

# Check if already initialized
INIT_STATUS=$(kubectl exec openbao-0 -n "$NAMESPACE" -- \
    bao status -format=json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['initialized'])" 2>/dev/null || echo "false")

if [ "$INIT_STATUS" = "True" ]; then
    log "OpenBao is already initialized. If you need to re-initialize, delete the PVCs and redeploy."
    log "To unseal manually: bao operator unseal <key> (run 3 times with different keys)"
    exit 0
fi

log "Step 2: Initializing OpenBao (key-shares=$KEY_SHARES, key-threshold=$KEY_THRESHOLD)..."
INIT_OUTPUT=$(kubectl exec openbao-0 -n "$NAMESPACE" -- \
    bao operator init -key-shares="$KEY_SHARES" -key-threshold="$KEY_THRESHOLD" -format=json)

# Parse keys and root token
# OpenBao 2.x uses 'unseal_keys_b64'; older Vault-compat builds use 'keys_base64'
UNSEAL_KEYS=$(echo "$INIT_OUTPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
keys = d.get('unseal_keys_b64') or d.get('keys_base64')
if not keys:
    print('ERROR: could not find unseal keys in init output. Available fields:', list(d.keys()), file=sys.stderr)
    sys.exit(1)
for i, k in enumerate(keys, 1):
    print(f'unseal_key_{i}={k}')
print(f'root_token={d[\"root_token\"]}')
")

ROOT_TOKEN=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['root_token'])")

# Extract individual keys into an array
declare -a KEYS=()
while IFS='=' read -r name value; do
    if [[ "$name" == unseal_key_* ]]; then
        KEYS+=("$value")
    fi
done <<< "$UNSEAL_KEYS"

log "Step 3: Writing keys to $OUTPUT_FILE..."
{
    echo "# OpenBao unseal keys — generated $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "# Keep this file secure. Do NOT commit it to git."
    echo ""
    echo "$INIT_OUTPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
keys = d.get('unseal_keys_b64') or d.get('keys_base64')
for i, k in enumerate(keys, 1):
    print(f'Unseal Key {i}: {k}')
print(f'Root Token:   {d[\"root_token\"]}')
"
} > "$OUTPUT_FILE"
log "Saved to $OUTPUT_FILE"

log "Step 4: Storing unseal keys in Kubernetes Secret ($SECRET_NAME)..."
kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found

# Build --from-literal args
FROM_LITERAL_ARGS=()
while IFS='=' read -r name value; do
    FROM_LITERAL_ARGS+=("--from-literal=${name}=${value}")
done <<< "$UNSEAL_KEYS"

kubectl create secret generic "$SECRET_NAME" \
    -n "$NAMESPACE" \
    "${FROM_LITERAL_ARGS[@]}"
log "Secret $SECRET_NAME created"

log "Step 5: Unsealing openbao-0 (applying $KEY_THRESHOLD of $KEY_SHARES keys)..."
for i in $(seq 0 $((KEY_THRESHOLD - 1))); do
    bao_exec openbao-0 operator unseal "${KEYS[$i]}"
done

log "openbao-0 unsealed. Waiting for it to become leader..."
sleep 10

log "Step 6: Unsealing remaining pods..."
for pod in "${PODS[@]:1}"; do
    log "Waiting for $pod..."
    wait_for_pod "$pod"
    sleep 3
    log "Unsealing $pod..."
    for i in $(seq 0 $((KEY_THRESHOLD - 1))); do
        bao_exec "$pod" operator unseal "${KEYS[$i]}" || true
    done
done

log ""
log "✓ OpenBao initialized and all pods unsealed."
log "  Root token stored in: $OUTPUT_FILE"
log "  Unseal keys stored in K8s secret: $SECRET_NAME"
log ""
log "Next steps:"
log "  1. Log in:  export BAO_ADDR=http://openbao.bento-dev.svc.cluster.local:8200"
log "              bao login <root-token>"
log "  2. Reconfigure Kubernetes auth: see openbao/KUBERNETES_AUTH_SETUP.md"
log "  3. Re-enable KV engine:         cd openbao && python creating_secret_engine.py"
