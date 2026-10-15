#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../../scripts/lib.sh"

section "Webapp Service Patch"

info "Patching webapp service type to LoadBalancer ..."
kubectl patch service webapp -n webapp -p '{"spec": {"type": "LoadBalancer"}}'
ok "Service type set to LoadBalancer"

info "Assigning MetalLB IP 192.168.104.55 to webapp ..."
kubectl patch service webapp -n webapp -p '{"metadata": {"annotations": {"metallb.universe.tf/loadBalancerIPs": "192.168.104.55"}}}'
ok "Load balancer IP assigned"

NODE_PORT=$(kubectl get svc webapp -n webapp -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
ok "Webapp is accessible at http://192.168.104.55"
info "From Mac via port-forward: ./port-forward.sh 80:${NODE_PORT}/TCP  →  http://localhost:8080"
