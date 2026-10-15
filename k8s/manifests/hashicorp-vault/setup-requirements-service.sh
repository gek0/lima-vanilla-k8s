#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

section "Vault Requirements"

info "Adding HashiCorp Helm repository ..."
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
ok "Helm repository updated"

if helm status vault -n vault &>/dev/null
then
  warn "Vault Helm release already exists — skipping install"
else
  info "Installing Vault via Helm ..."
  helm install vault hashicorp/vault \
    --namespace vault \
    --create-namespace \
    --values "${SCRIPT_DIR}/helm-vault-raft-values.yaml"
  ok "Vault Helm release installed"
fi
