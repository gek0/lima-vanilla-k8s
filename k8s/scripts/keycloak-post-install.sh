#!/usr/bin/env bash
# Run after Keycloak ArgoCD Application is Healthy.
# Creates OAuth clients for Grafana, ArgoCD and Vault, then stores secrets in Vault.
set -e
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KEYS_FILE="${SCRIPT_DIR}/../../secrets/cluster-keys.json"
ROOT_TOKEN=$(jq -r ".root_token" "${KEYS_FILE}")

KEYCLOAK_URL="http://keycloak.local.io"
REALM="master"
ADMIN_USER="admin"
ADMIN_PASS="admin"

section "Keycloak Admin Token"
info "Fetching Keycloak admin access token ..."
ADMIN_TOKEN=$(curl -sf -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=${ADMIN_USER}" \
  -d "password=${ADMIN_PASS}" \
  -d "grant_type=password" | jq -r '.access_token')
ok "Admin token obtained"

create_client() {
  local client_id=$1
  local redirect_uris=$2
  local secret

  info "Creating Keycloak client: ${client_id} ..."
  curl -sf -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"clientId\": \"${client_id}\",
      \"enabled\": true,
      \"protocol\": \"openid-connect\",
      \"publicClient\": false,
      \"standardFlowEnabled\": true,
      \"redirectUris\": ${redirect_uris}
    }" || warn "Client ${client_id} may already exist — continuing"

  local client_uuid
  client_uuid=$(curl -sf "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=${client_id}" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" | jq -r '.[0].id')

  secret=$(curl -sf -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/client-secret" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" | jq -r '.value')

  echo "$secret"
}

section "Keycloak — Grafana Client"
GRAFANA_SECRET=$(create_client "grafana" '["http://grafana.local.io/*","http://grafana.local.io/login/generic_oauth"]')
kubectl exec vault-0 -n vault -- vault login "$ROOT_TOKEN" > /dev/null
kubectl exec vault-0 -n vault -- vault kv put secret/keycloak/grafana client_secret="${GRAFANA_SECRET}"
ok "Grafana client secret stored at secret/keycloak/grafana"

section "Keycloak — ArgoCD Client"
ARGOCD_SECRET=$(create_client "argocd" '["http://argocd.local.io/*"]')
kubectl exec vault-0 -n vault -- vault kv put secret/keycloak/argocd client_secret="${ARGOCD_SECRET}"
ok "ArgoCD client secret stored at secret/keycloak/argocd"

section "Keycloak — Vault Client"
VAULT_SECRET=$(create_client "vault" '["http://vault.local.io/*","http://vault.local.io/ui/vault/auth/oidc/oidc/callback"]')
kubectl exec vault-0 -n vault -- vault kv put secret/keycloak/vault client_secret="${VAULT_SECRET}"
ok "Vault client secret stored at secret/keycloak/vault"

section "Done"
ok "All Keycloak clients created and secrets stored in Vault"
info "ESO will sync secrets to Grafana and ArgoCD automatically"
info "Re-run vault-post-install.sh to configure Vault OIDC auth"
