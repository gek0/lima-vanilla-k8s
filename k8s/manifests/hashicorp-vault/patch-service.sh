#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

section "Vault Service Patch"

info "Patching vault service type to LoadBalancer ..."
kubectl patch service vault -n vault -p '{"spec": {"type": "LoadBalancer"}}'
ok "Service type set to LoadBalancer"

info "Assigning MetalLB IP 192.168.104.53 to vault ..."
kubectl patch service vault -n vault -p '{"metadata": {"annotations": {"metallb.universe.tf/loadBalancerIPs": "192.168.104.53"}}}'
ok "Load balancer IP assigned"

NODE_PORT=$(kubectl get svc vault -n vault -o jsonpath='{.spec.ports[?(@.port==8200)].nodePort}')
ok "Vault is accessible at http://192.168.104.53:8200"
info "From Mac via port-forward: ./port-forward.sh 8200:${NODE_PORT}/TCP  →  http://localhost:8200"
