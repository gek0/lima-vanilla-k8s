#!/usr/bin/env bash
set -e

componentsDir="/root/k8s/components"

## install Calico as CNI
kubectl apply -f ${componentsDir}/calico/calico.yaml

## install Metrics Server - for HPA and VPA components
kubectl apply -f ${componentsDir}/metrics-server/components.yaml
# patch for self-signed certificates and tolerations for master/control-plane nodes
kubectl patch deployment metrics-server -n kube-system \
  --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

## install istioctl and Istio ingress
echo "...lets wait a bit for metrics-server to be ready..."
sleep 15
cd /opt
curl -sL https://istio.io/downloadIstio | sh -
istioDir=$(find /opt -maxdepth 1 -name "istio*" -type d)
ln -fs $istioDir/bin/istioctl /usr/local/bin/
echo "istioctl is ready at $(which istioctl)"
istioctl x precheck
istioctl install --skip-confirmation
kubectl apply -f ${componentsDir}/istio/gateway.yaml

## install MetalLB (emulated network loadbalancer)
##  https://metallb.universe.tf/installation/
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl apply -f - -n kube-system
kubectl apply -f ${componentsDir}/metallb/crds.yaml --server-side
kubectl apply -f ${componentsDir}/metallb/metallb-native.yaml
echo "...lets wait a bit for metallb-controller to be ready..."
sleep 20
kubectl apply -f ${componentsDir}/metallb/webhook.yaml
kubectl apply -f ${componentsDir}/metallb/configuration.yaml

## Install monitoring stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install loki grafana/loki-stack -n monitoring --create-namespace --set promtail.enabled=true
kubectl create secret generic monitoring-grafana -n monitoring --from-literal=admin-user=admin --from-literal=admin-password=admin
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring -f ${componentsDir}/monitoring/kube-prometheus-stack-values.yaml

echo -e "\nAll k8s components installed and ready!"
