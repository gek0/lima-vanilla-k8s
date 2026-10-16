#!/usr/bin/env bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

componentsDir="/root/k8s/components"

section "k8s component installation"
info "Components directory: $componentsDir"

## Calico CNI
section "Calico CNI"
info "Installing Calico as the cluster CNI ..."
kubectl apply -f ${componentsDir}/calico/calico.yaml
ok "Calico applied"

## Metrics Server
section "Metrics Server"
info "Installing Metrics Server ..."
kubectl apply -f ${componentsDir}/metrics-server/components.yaml
info "Patching for self-signed certificates and control-plane tolerations ..."
kubectl patch deployment metrics-server -n kube-system \
  --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
ok "Metrics Server applied and patched"

## Istio
section "Istio Service Mesh"
warn "Waiting 15s for Metrics Server to become ready ..."
sleep 15

info "Downloading Istio installer ..."
cd /opt
curl -sL https://istio.io/downloadIstio | sh -

istioDir=$(find /opt -maxdepth 1 -name "istio*" -type d)
ln -fs $istioDir/bin/istioctl /usr/local/bin/
ok "istioctl installed at $(which istioctl)"

info "Running Istio pre-installation checks ..."
istioctl x precheck

info "Installing Istio (default profile) ..."
istioctl install --skip-confirmation
ok "Istio installed"

info "Applying Istio gateway ..."
kubectl apply -f ${componentsDir}/istio/gateway.yaml
ok "Istio gateway applied"

## MetalLB
section "MetalLB Load Balancer"
info "Enabling strictARP on kube-proxy ..."
kubectl get configmap kube-proxy -n kube-system -o yaml | \
  sed -e "s/strictARP: false/strictARP: true/" | \
  kubectl apply -f - -n kube-system
ok "kube-proxy strictARP enabled"

info "Applying MetalLB CRDs ..."
kubectl apply -f ${componentsDir}/metallb/crds.yaml --server-side

info "Applying MetalLB native manifest ..."
kubectl apply -f ${componentsDir}/metallb/metallb-native.yaml

warn "Waiting 20s for MetalLB controller to become ready ..."
sleep 20

info "Applying MetalLB webhook configuration ..."
kubectl apply -f ${componentsDir}/metallb/webhook.yaml

info "Applying MetalLB IP pool configuration ..."
kubectl apply -f ${componentsDir}/metallb/configuration.yaml
ok "MetalLB installed and configured"

## Local Path Provisioner
section "Local Path Provisioner"
info "Installing local-path-provisioner for dynamic PV provisioning ..."
kubectl apply -f ${componentsDir}/local-path-provisioner/local-path-storage.yaml
ok "local-path storage class available"

## Crossplane
section "Crossplane"
info "Adding Crossplane Helm repository ..."
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update
ok "Helm repository updated"

info "Creating crossplane-system namespace ..."
kubectl create namespace crossplane-system --dry-run=client -o yaml | kubectl apply -f -

info "Installing Crossplane ..."
helm upgrade --install crossplane --namespace crossplane-system crossplane-stable/crossplane
ok "Crossplane installed"

echo
ok "All k8s components installed and ready"
