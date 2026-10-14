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

kubectl apply -f ${componentsDir}/metallb/metallb-native.yaml
kubectl apply -f ${componentsDir}/metallb/configuration.yaml

echo -e "\nall k8s components installed and ready"
