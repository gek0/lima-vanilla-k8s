#!/usr/bin/env bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests/cluster-access"
DEFAULT_NAMESPACE="kube-system"

export KUBECONFIG=/etc/kubernetes/admin.conf

write_kubeconfig() {
  local context_name=$1 user_name=$2 token=$3 output=$4
  cat << EOF > "${output}"
apiVersion: v1
kind: Config
current-context: ${context_name}
contexts:
- name: ${context_name}
  context:
    cluster: ${CURRENT_CLUSTER}
    user: ${user_name}
    namespace: ${DEFAULT_NAMESPACE}
clusters:
- name: ${CURRENT_CLUSTER}
  cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${CLUSTER_SERVER}
users:
- name: ${user_name}
  user:
    token: ${token}
EOF
  ok "Kubeconfig written: ${output}"
}

section "Installing k8s components"
if [[ "$1" == "--skip-install" ]]; then
  warn "Skipping component installation (--skip-install passed)"
else
  "${SCRIPT_DIR}/install-k8s-components.sh"
fi

# Apply cluster-access service accounts, RBAC and token secrets (admin + reader)
section "Creating cluster access"
kubectl apply -f "${MANIFESTS_DIR}/cluster-admin.yaml"
kubectl apply -f "${MANIFESTS_DIR}/cluster-reader.yaml"
ok "Cluster access resources applied"

section "Generating kubeconfigs"
info "Reading cluster info ..."
CURRENT_CONTEXT=$(kubectl config current-context)
CURRENT_CLUSTER=$(kubectl config view --raw -o=go-template='{{range .contexts}}{{if eq .name "'''${CURRENT_CONTEXT}'''"}}{{ index .context "cluster" }}{{end}}{{end}}')
CLUSTER_CA=$(kubectl config view --raw -o=go-template='{{range .clusters}}{{if eq .name "'''${CURRENT_CLUSTER}'''"}}"{{with index .cluster "certificate-authority-data" }}{{.}}{{end}}"{{ end }}{{ end }}')
CLUSTER_SERVER=$(kubectl config view --raw -o=go-template='{{range .clusters}}{{if eq .name "'''${CURRENT_CLUSTER}'''"}}{{ .cluster.server }}{{end}}{{ end }}')

ADMIN_TOKEN=$(kubectl -n ${DEFAULT_NAMESPACE} get secret cluster-admin-token-secret -o=go-template='{{.data.token}}' | base64 --decode)
write_kubeconfig "k8s-admin" "cluster-admin" "${ADMIN_TOKEN}" "${MANIFESTS_DIR}/cluster-admin-config.yaml"

READER_TOKEN=$(kubectl -n ${DEFAULT_NAMESPACE} get secret cluster-reader-token-secret -o=go-template='{{.data.token}}' | base64 --decode)
write_kubeconfig "k8s-reader" "cluster-reader" "${READER_TOKEN}" "${MANIFESTS_DIR}/cluster-reader-config.yaml"

section "Worker node join command"
kubeadm token create --print-join-command

section "Merging local kubeconfig"
"${SCRIPT_DIR}/converge-kube-config.sh"
