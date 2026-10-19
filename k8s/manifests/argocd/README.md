# ArgoCD

GitOps setup for the Lima vanilla Kubernetes cluster. ArgoCD runs in-cluster and continuously reconciles everything in the gitops repository against the live cluster state.

## How it works

```
sample-k8s-argocd-bootstrap   ← install ArgoCD + apply projects + root app (one manual kubectl apply)
        │
        ▼
  root app watches sample-k8s-gitops/argocd/ recursively
        │
        ├── any Application or ApplicationSet pushed there is picked up automatically
        └── *-values.yaml files are excluded (not K8s resources — referenced via $values multi-source)
```

Changes to the **gitops repo** (`sample-k8s-gitops`) are fully automatic — push and ArgoCD reconciles.
Changes to the **bootstrap repo** (`sample-k8s-argocd-bootstrap`) require a manual `kubectl apply -R -f core/`.

## Accessing ArgoCD

| Method | URL |
|---|---|
| In-cluster (MetalLB) | dynamic — `kubectl get svc argocd-server -n argocd` |
| Virtual host (Istio) | http://argocd.local.io |
| Host port-forward | http://localhost:8080 (via `port-forward.sh`) |

## CLI

ArgoCD runs in insecure mode (TLS terminated by Istio) — always connect on port 80 with `--plaintext`.

### Login — one-time per machine, context is persisted in `~/.config/argocd/config`

```bash
ARGOCD_IP=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
ARGOCD_PASS=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)

argocd login "${ARGOCD_IP}:80" --plaintext --username admin --password "${ARGOCD_PASS}"
```

### Apps

```bash
argocd app list                          # list all apps with sync/health status
argocd app get vault                     # detailed status for a single app
argocd app resources vault               # K8s resources managed by the app
argocd app resources vault --output tree # same, as a resource tree
argocd app diff vault                    # diff between live state and git
argocd app sync vault                    # trigger a manual sync
argocd app wait vault --health           # block until app is Healthy
argocd app history vault                 # sync history
argocd app rollback vault <id>           # roll back to a previous sync
```

### Projects

```bash
argocd proj list                         # list all AppProjects
argocd proj get cluster-ops              # show allowed repos and destinations
```

### Other

```bash
argocd version                           # client and server version
argocd account get-user-info             # current logged-in user
argocd context                           # show saved login contexts
argocd logout "${ARGOCD_IP}:80"          # clear saved context
```
