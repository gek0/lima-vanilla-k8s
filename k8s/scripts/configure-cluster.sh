#!/usr/bin/env bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests/cluster-admin"

export KUBECONFIG=/etc/kubernetes/admin.conf

section "Cluster admin setup"
info "Using kubeconfig: $KUBECONFIG"

section "Installing k8s components"
"${SCRIPT_DIR}/install-k8s-components.sh"

section "Creating Service Account and RBAC"
export SERVICE_ACCOUNT="mb-cluster-admin"
export DEFAULT_NAMESPACE="kube-system"

info "Applying service account: $SERVICE_ACCOUNT in namespace $DEFAULT_NAMESPACE ..."
kubectl apply -f "${MANIFESTS_DIR}/cluster-admin-sa.yaml"

info "Applying RBAC rules ..."
kubectl apply -f "${MANIFESTS_DIR}/cluster-admin-rbac.yaml"

info "Applying token secret ..."
kubectl apply -f "${MANIFESTS_DIR}/cluster-admin-secret.yaml"
ok "Service account, RBAC, and token secret applied"

section "Generating Cluster Admin kubeconfig"
info "Reading cluster configuration ..."

export USER_TOKEN_VALUE=$(kubectl -n $DEFAULT_NAMESPACE get secret "${SERVICE_ACCOUNT}-token-secret" -o=go-template='{{.data.token}}' | base64 --decode)
export CURRENT_CONTEXT=$(kubectl config current-context)
export CURRENT_CLUSTER=$(kubectl config view --raw -o=go-template='{{range .contexts}}{{if eq .name "'''${CURRENT_CONTEXT}'''"}}{{ index .context "cluster" }}{{end}}{{end}}')
export CLUSTER_CA=$(kubectl config view --raw -o=go-template='{{range .clusters}}{{if eq .name "'''${CURRENT_CLUSTER}'''"}}"{{with index .cluster "certificate-authority-data" }}{{.}}{{end}}"{{ end }}{{ end }}')
export CLUSTER_SERVER=$(kubectl config view --raw -o=go-template='{{range .clusters}}{{if eq .name "'''${CURRENT_CLUSTER}'''"}}{{ .cluster.server }}{{end}}{{ end }}')

info "Writing kubeconfig to ${MANIFESTS_DIR}/cluster-admin-config.yaml ..."

cat << EOF > "${MANIFESTS_DIR}/cluster-admin-config.yaml"
apiVersion: v1
kind: Config
current-context: ${CURRENT_CONTEXT}
contexts:
- name: ${CURRENT_CONTEXT}
  context:
    cluster: ${CURRENT_CONTEXT}
    user: ${SERVICE_ACCOUNT}
    namespace: ${DEFAULT_NAMESPACE}
clusters:
- name: ${CURRENT_CONTEXT}
  cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${CLUSTER_SERVER}
users:
- name: ${SERVICE_ACCOUNT}
  user:
    token: ${USER_TOKEN_VALUE}
EOF

ok "Kubeconfig written to ${MANIFESTS_DIR}/cluster-admin-config.yaml"

section "Worker Node Join Command"
info "Generating join token for new worker nodes ..."
kubeadm token create --print-join-command
ok "Use the command above to join additional worker nodes to the cluster"

section "Creating local kubeconfig..."
"${SCRIPT_DIR}/converge-kube-config.sh"
