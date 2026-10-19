#!/usr/bin/env bash
# Run after ArgoCD has synced Vault. Handles init, unseal, and raft join — imperative
# operations that ArgoCD cannot manage. Service type and MetalLB IP are set in Helm values.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KEYS_FILE="${SCRIPT_DIR}/cluster-keys.json"

section "Vault Initialization"

info "Waiting for vault-0 to be Running ..."
until kubectl get pod vault-0 -n vault -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"
do
  warn "vault-0 not yet running — retrying in 5s ..."
  sleep 5
done
ok "vault-0 is running"

VAULT_INITIALIZED=$(kubectl exec vault-0 -n vault -- vault status 2>&1 | grep "^Initialized" | awk '{print $2}' || true)

if [[ "$VAULT_INITIALIZED" == "true" ]]
then
  warn "Vault already initialized — loading keys from ${KEYS_FILE}"
else
  info "Initializing Vault with 1 key share and 1 key threshold ..."
  kubectl exec vault-0 -n vault -- vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > "${KEYS_FILE}"
  ok "Vault initialized — keys saved to cluster-keys.json"
fi

VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" "${KEYS_FILE}")
ROOT_TOKEN=$(jq -r ".root_token" "${KEYS_FILE}")

section "Unsealing vault-0"
kubectl exec vault-0 -n vault -- vault operator unseal "$VAULT_UNSEAL_KEY"
ok "vault-0 unsealed"

section "Raft Cluster Join + Unseal"
for pod in vault-1 vault-2
do
  info "Waiting for ${pod} to be Running ..."
  until kubectl get pod "${pod}" -n vault -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"
  do
    warn "${pod} not yet running — retrying in 5s ..."
    sleep 5
  done

  info "Joining ${pod} to raft cluster ..."
  kubectl exec "${pod}" -n vault -- vault operator raft join http://vault-0.vault-internal:8200

  info "Unsealing ${pod} ..."
  kubectl exec "${pod}" -n vault -- vault operator unseal "$VAULT_UNSEAL_KEY"
  ok "${pod} joined and unsealed"
done

section "Vault Ready"
ok "Vault is accessible at http://192.168.104.53:8200"
info "Root token: ${ROOT_TOKEN}"
info "From Host: ./port-forward.sh 8200:8200/TCP  →  http://localhost:8200"
