#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ADMIN_CONFIG="${SCRIPT_DIR}/../manifests/cluster-access/cluster-admin-config.yaml"
READER_CONFIG="${SCRIPT_DIR}/../manifests/cluster-access/cluster-reader-config.yaml"

section "Kubeconfig Merge"

if cp ~/.kube/config ~/.kube/config-backup 2>/dev/null; then
  ok "Existing kubeconfig backed up to ~/.kube/config-backup"
else
  warn "No existing kubeconfig found, skipping backup"
fi

echo
warn "Press enter to continue with the kubeconfig merge..."
read

section "Merging Configurations"

KUBECONFIG_PARTS="${HOME}/.kube/config:${ADMIN_CONFIG}"

if [[ -f "${READER_CONFIG}" ]]; then
  KUBECONFIG_PARTS="${KUBECONFIG_PARTS}:${READER_CONFIG}"
  info "Merging admin and reader contexts ..."
else
  warn "Reader config not found — re-run configure-cluster.sh on master to generate it"
  info "Merging admin context only ..."
fi

export KUBECONFIG="${KUBECONFIG_PARTS}"
kubectl config view --flatten > all-in-one-kubeconfig.yaml
mv all-in-one-kubeconfig.yaml ~/.kube/config

echo
ok "Kubeconfig merged and saved to ~/.kube/config"
info "Available contexts:"
kubectl config get-contexts
