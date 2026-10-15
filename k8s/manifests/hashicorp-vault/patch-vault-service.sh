#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

section "Vault Service Patch"

info "Patching vault service type to LoadBalancer ..."
kubectl patch service vault -n vault -p '{"spec": {"type": "LoadBalancer"}}'
ok "Service type set to LoadBalancer"

info "Assigning MetalLB IP 192.168.104.53 to vault ..."
kubectl patch service vault -n vault -p '{"metadata": {"annotations": {"metallb.universe.tf/loadBalancerIPs": "192.168.104.53"}}}'
ok "Load balancer IP assigned"

echo
ok "Vault service patched successfully"
