# Vanilla K8s in Lima-VM
![Lima-VM and Kubernetes](https://i.imgur.com/V2afcyF.png)

A fully-automated kubeadm cluster running on [Lima-VM](https://lima-vm.io) — tested on macOS (Apple Silicon). Refreshed upgrade from [vagrant-vanilla-k8s](https://github.com/gek0/vagrant-vanilla-k8s), updated for ARM and the latest Kubernetes release (v1.37).

---

## Quick Start

```bash
# 1. Provision nodes (see node-definitions/README.md)
#    Defaults: 1 master + 2 workers

# 2. Join workers — master prints the kubeadm join command on first boot
limactl shell master-1   # copy the join command
limactl shell worker-1   # paste & run it (repeat for all workers)

# 3. Configure the cluster from master
limactl shell master-1
sudo -i
cd /root/k8s
./scripts/configure-cluster.sh          # full install
./scripts/configure-cluster.sh --skip-install   # subsequent runs: skip component reinstall
```

The script installs all components, creates an admin user, and merges the kubeconfig into `~/.kube/config` on master-1 node automatically.


## Next steps

- run `k8s/scripts/manifest-installer.sh` and select `argocd`
    - after ArgoCD is installed, apply the `core` and `applications` manifests once (from `sample-k8s-argocd-bootstrap` repository) — ArgoCD reconciles them continuously from that point
```bash
# create projects
kubectl apply -f k8s/manifests/argocd/sample-k8s-argocd-bootstrap/core/projects/

# create app-of-apps ("root" application start syncing all other ones)
kubectl apply -f k8s/manifests/argocd/sample-k8s-argocd-bootstrap/core/applications/
```
- once that is done proceed to Vault unseal and initial secrets configuration -> **prepare IAM User credentials at this step for Crossplane!**
    - limit IAM user credentials at your will depeding on the resources you plan to provision (default needed: VPC + S3 R/W access)
    - ` ./k8s/scripts/vault-post-install.sh`

- verify installation in cluster and check next sections

## Cluster components

| Component | Notes |
|---|---|
| [Calico](https://www.tigera.io/project-calico/) | CNI |
| [Metrics Server](https://github.com/kubernetes-sigs/metrics-server) | Node metrics (needed for HPA, ...) |
| [Istio](https://istio.io) | Ingress + `istioctl` |
| [MetalLB](https://metallb.universe.tf) | L2 mode, pool `192.168.104.50–90` — update range in `k8s/components/metallb/configuration.yaml` |
| [Local Path Provisioner](https://github.com/rancher/local-path-provisioner) | Dynamic PV via node filesystem |

All necessary binaries and tools (like `k9s`, `kubectl` and `argocd`, ...) are available on master-1 for in-cluster work. Check `node-definitions/scripts/master-provision.sh` for full setup.

## ArgoCD-managed services

Everything below is deployed and continuously reconciled by ArgoCD after the initial bootstrap. See `k8s/manifests/argocd/sample-k8s-gitops/` for all Application definitions.

| Service | ArgoCD App | Notes |
|---|---|---|
| [Vault](https://www.vaultproject.io) | `vault` | HA Raft, 3 replicas — run `k8s/scripts/vault-post-install.sh` once after first sync |
| Vault webapp | `vault-webapp` | Demo app reading secrets from Vault via Kubernetes auth |
| [Grafana](https://grafana.com) | `kube-prometheus-stack` | admin / admin — Prometheus + Loki datasources pre-wired |
| [Prometheus](https://prometheus.io) | `kube-prometheus-stack` | ClusterIP only — accessible via Grafana or `kubectl port-forward` |
| [Loki](https://grafana.com/oss/loki/) | `loki-stack` | Log aggregation — ClusterIP only |
| [External Secrets Operator](https://external-secrets.io) | `external-secrets` | Syncs secrets from Vault into K8s Secrets |
| ESO Vault store | `eso-vault-store` | `ClusterSecretStore` wired to Vault via Kubernetes auth |
| [Crossplane](https://crossplane.io) | `crossplane` | AWS infra provisioning |
| Crossplane AWS providers | `crossplane-providers` | upbound provider-family-aws, provider-aws-s3, provider-aws-ec2 |
| Crossplane devops-aws config | `crossplane-devops-aws-config` | ProviderConfig + ESO-synced credentials for devops team |
| S3 buckets (dev + prod) | `crossplane-devops-aws` (AppSet) | Helm chart `charts/crossplane/aws/s3-bucket` — values in `services/crossplane/aws/devops/{env}/` — **manual sync only** |
| VPC (dev only) | `crossplane-devops-aws` (AppSet) | Helm chart `charts/crossplane/aws/vpc` — **manual sync only** |
| nginx HPA sample | `nginx-hpa` | Sample app with HPA from `sample-k8s-app` repo |

> **Manual sync** — Applications marked as manual sync are created by ArgoCD but will show `OutOfSync` until explicitly triggered. This is intentional for cloud infrastructure resources (S3, VPC) to prevent accidental provisioning. Trigger with `argocd app sync <app-name>` or from the ArgoCD UI.

---

## Exposed Services

All LoadBalancer services get IPs dynamically from the MetalLB pool. Find them with:

```bash
kubectl get svc -A --field-selector spec.type=LoadBalancer
```

| Service | Access |
|---|---|
| [ArgoCD](https://argo-cd.readthedocs.io) | See `k8s/manifests/argocd/README.md` |
| [Vault](https://www.vaultproject.io) | See `k8s/manifests/argocd/sample-k8s-gitops/README.md` — run `k8s/scripts/vault-post-install.sh` once after first sync |
| [Grafana](https://grafana.com) | Managed by ArgoCD — admin / admin |
| Vault webapp demo | Reads secrets from Vault via k8s SA auth |

> Prometheus and Alertmanager are ClusterIP only — access via Grafana or `kubectl port-forward`.

### Accessing services from your Host

```bash
./port-forward.sh              # auto-discovers all LoadBalancer services and forwards each
./port-forward.sh 80:30718/TCP # forward a single service
```

Privileged ports (< 1024) are remapped to `port + 8000` (e.g. port 80 → localhost:8080). Press Ctrl+C to stop all tunnels.

---

## GitOps — Submodules

Three submodules under `k8s/manifests/argocd/` form the GitOps layer:

| Submodule | Repo | Purpose |
|---|---|---|
| `sample-k8s-argocd-bootstrap` | [gek0/sample-k8s-argocd-bootstrap](https://github.com/gek0/sample-k8s-argocd-bootstrap) | Installs ArgoCD; owns AppProjects, repo credentials, RBAC, root app |
| `sample-k8s-gitops` | [gek0/sample-k8s-gitops](https://github.com/gek0/sample-k8s-gitops) | ArgoCD Application/ApplicationSet definitions; Helm values, per-env manifests |
| `sample-k8s-app` | [gek0/sample-k8s-app](https://github.com/gek0/sample-k8s-app) | Kubernetes manifests for the nginx sample app (Deployment, Service, HPA) |

```bash
git submodule update --init --recursive    # first-time init
git submodule update --remote --recursive  # pull latest from all submodules
```

---

## Adding additional services

Run the interactive installer from master to install any service in `k8s/manifests/`:
- either add your services to ArgoCD or directly to its own directory for simple service installations and tests

```bash
./scripts/manifest-installer.sh           # interactive menu
./scripts/manifest-installer.sh --delete  # remove all resources for a selected service
```

### Service directory layout

Create a subdirectory under `k8s/manifests/<service-name>/` — the installer picks it up automatically:

| File | Purpose |
|---|---|
| `setup-requirements-service.sh` | Runs first — Helm installs, repo adds, prerequisites |
| `namespace.yaml` | Applied before all other manifests |
| `*.yaml` | Applied alphabetically after namespace |
| `wait-for` | One `<resource-type>/<name> <namespace>` per line — polls each before `patch-service.sh` |
| `patch-service.sh` | Runs last — LoadBalancer patching, init steps, password retrieval |

Example `wait-for`:
```
deployment/my-service my-namespace
statefulset/my-db my-namespace
```

---

## Secrets

Runtime secrets are written to `secrets/` at the repo root (gitignored — never committed).

| File | Created by | Contents |
|---|---|---|
| `secrets/cluster-keys.json` | `k8s/scripts/vault-post-install.sh` | Vault unseal key and root token |

---

## Kubeconfig

`configure-cluster.sh` merges the cluster admin kubeconfig automatically. To re-merge at any time and use on the `master-1` node:

```bash
k8s/scripts/converge-kube-config.sh
```
