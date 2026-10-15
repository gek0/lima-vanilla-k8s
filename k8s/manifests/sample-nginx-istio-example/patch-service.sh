#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

section "Sample App Service Patch"

info "Patching sample-app service type to LoadBalancer ..."
kubectl patch service sample-app -n sample-app -p '{"spec": {"type": "LoadBalancer"}}'
ok "Service type set to LoadBalancer"

info "Assigning MetalLB IP 192.168.104.56 to sample-app ..."
kubectl patch service sample-app -n sample-app -p '{"metadata": {"annotations": {"metallb.universe.tf/loadBalancerIPs": "192.168.104.56"}}}'
ok "Load balancer IP assigned"

NODE_PORT=$(kubectl get svc sample-app -n sample-app -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
ok "Sample App is accessible at http://192.168.104.56"
info "From Mac via port-forward: ./port-forward.sh 80:${NODE_PORT}/TCP  →  http://localhost:8080"
