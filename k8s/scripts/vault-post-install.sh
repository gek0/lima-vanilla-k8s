#!/usr/bin/env bash
# Run after ArgoCD has synced Vault. Handles init, unseal, and raft join — imperative
# operations that ArgoCD cannot manage. Service type and MetalLB IP are set in Helm values.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KEYS_FILE="${SCRIPT_DIR}/../../secrets/cluster-keys.json"

section "Vault Initialization"

info "Waiting for vault-0 to accept connections ..."
until kubectl exec vault-0 -n vault -- vault status 2>/dev/null | grep -q "^Initialized"
do
  warn "vault-0 not yet accepting connections — retrying in 5s ..."
  sleep 5
done
ok "vault-0 is accepting connections"

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

section "Raft Cluster Stability"
info "Waiting for Vault raft cluster to elect a stable leader ..."
until kubectl exec vault-0 -n vault -- vault status 2>/dev/null | grep -qE "HA Mode\s+(active|standby)"
do
  warn "Leader election in progress — retrying in 5s ..."
  sleep 5
done
ok "Vault cluster has a stable leader"

info "Finding active Vault pod ..."
VAULT_ACTIVE_POD=$(kubectl get pod -n vault -l vault-active=true -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "vault-0")
ok "Active pod: ${VAULT_ACTIVE_POD}"

section "Vault Configuration"
info "Logging into ${VAULT_ACTIVE_POD} ..."
kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- vault login "$ROOT_TOKEN"

info "Enabling kv-v2 secrets engine ..."
kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- sh -c 'vault secrets list | grep -q "^secret/" || vault secrets enable -path=secret kv-v2'

info "Enabling Kubernetes auth ..."
kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- sh -c 'vault auth list | grep -q "^kubernetes/" || vault auth enable kubernetes'
kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- sh -c 'vault write auth/kubernetes/config kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"'
ok "Kubernetes auth configured"

section "Vault — Webapp"
kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- sh -c 'vault policy write webapp - <<EOF
path "secret/data/webapp/config" {
  capabilities = ["read"]
}
EOF'
ok "webapp policy created"

kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- vault write auth/kubernetes/role/webapp \
  bound_service_account_names=webapp \
  bound_service_account_namespaces=github-personal-vault-webapp \
  policies=webapp \
  ttl=24h
ok "webapp Kubernetes auth role created"

info "Creating placeholder webapp secret — update values after install ..."
kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- vault kv put secret/webapp/config username="user" password="pass"
ok "webapp secret created at secret/webapp/config"

section "Vault — ESO"
kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- sh -c 'vault policy write eso - <<EOF
path "secret/data/*" {
  capabilities = ["read"]
}
EOF'
ok "ESO policy created"

kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- vault write auth/kubernetes/role/eso \
  bound_service_account_names=eso-vault-auth \
  bound_service_account_namespaces=external-secrets \
  policies=eso \
  ttl=1h
ok "ESO Kubernetes auth role created"

section "Vault — Crossplane AWS (devops-infra-aws)"
if kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- vault kv get secret/crossplane/devops-aws &>/dev/null
then
  warn "secret/crossplane/devops-aws already exists — skipping"
else
  read -rp "AWS Access Key ID: " AWS_KEY_ID
  read -rsp "AWS Secret Access Key: " AWS_SECRET_KEY
  echo

  info "Storing AWS credentials in Vault at secret/crossplane/devops-aws ..."
  CREDS_B64=$(printf '[default]\naws_access_key_id = %s\naws_secret_access_key = %s\n' "$AWS_KEY_ID" "$AWS_SECRET_KEY" | base64 -w 0)
  kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- sh -c "echo '${CREDS_B64}' | base64 -d > /tmp/aws-creds && vault kv put secret/crossplane/devops-aws credentials=@/tmp/aws-creds && rm /tmp/aws-creds"
  ok "AWS credentials stored — ESO will sync to crossplane-creds-devops-aws in github-personal-crossplane-devops-aws"
fi

section "Vault — Keycloak OIDC Auth"
if kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- vault auth list 2>/dev/null | grep -q "^oidc/"
then
  warn "Vault OIDC auth already configured — skipping"
else
  VAULT_OIDC_SECRET=$(kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- vault kv get -field=client_secret secret/keycloak/vault 2>/dev/null || true)
  if [[ -z "$VAULT_OIDC_SECRET" ]]
  then
    warn "secret/keycloak/vault not found — skipping Vault OIDC setup"
    warn "Run k8s/scripts/keycloak-post-install.sh first to create Keycloak clients and store secrets"
  else
    info "Enabling OIDC auth method ..."
    kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- vault auth enable oidc

    kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- vault write auth/oidc/config \
      oidc_discovery_url="http://keycloak.local.io/realms/master" \
      oidc_client_id="vault" \
      oidc_client_secret="${VAULT_OIDC_SECRET}" \
      default_role="default"

    kubectl exec "${VAULT_ACTIVE_POD}" -n vault -- vault write auth/oidc/role/default \
      bound_audiences="vault" \
      allowed_redirect_uris="http://vault.local.io/ui/vault/auth/oidc/oidc/callback" \
      user_claim="sub" \
      policies="default" \
      ttl=8h
    ok "Vault OIDC auth configured — users can now log in via Keycloak"
  fi
fi

section "Vault Ready"
ok "Vault is accessible at http://192.168.104.53:8200"
info "Root token: ${ROOT_TOKEN}"
info "From Host: ./port-forward.sh 8200:8200/TCP  →  http://localhost:8200"
