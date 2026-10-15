#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CLUSTER_CONFIG="${SCRIPT_DIR}/../manifests/cluster-admin/cluster-admin-config.yaml"

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
info "Merging ~/.kube/config with ${CLUSTER_CONFIG} ..."

export KUBECONFIG=~/.kube/config:${CLUSTER_CONFIG}
kubectl config view --flatten > all-in-one-kubeconfig.yaml
mv all-in-one-kubeconfig.yaml ~/.kube/config

echo
ok "Kubeconfig merged and saved to ~/.kube/config"
