#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../lib.sh"

section "ArgoCD Service Patch"

info "Patching argocd-server service type to LoadBalancer ..."
kubectl patch service argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
ok "Service type set to LoadBalancer"

info "Assigning MetalLB IP 192.168.104.52 to argocd-server ..."
kubectl patch service argocd-server -n argocd -p '{"metadata": {"annotations": {"metallb.universe.tf/loadBalancerIPs": "192.168.104.52"}}}'
ok "Load balancer IP assigned"

info "Restarting argocd-server deployment ..."
kubectl rollout restart deployment argocd-server -n argocd
ok "Deployment rollout triggered"

section "ArgoCD Admin Password"
info "Fetching initial admin password ..."
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
ok "ArgoCD is accessible at http://192.168.104.52"
