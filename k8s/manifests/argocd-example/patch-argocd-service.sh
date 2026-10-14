#!/usr/bin/env bash

kubectl patch service argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
kubectl patch service argocd-server -n argocd -p '{"metadata": {"annotations": {"metallb.universe.tf/loadBalancerIPs": "192.168.104.52"}}}'
kubectl rollout restart deployment argocd-server -n argocd

echo "==== ArgoCD initial admin password ===="
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
