# Vanilla K8s in Lima-VM
![Lima-VM and Kubernetes](https://i.imgur.com/V2afcyF.png)

- latest K8s install (v1.37 at the time) using containerd runtime on Lima-VM nodes (adapted for MacOS)!
- this is a refreshed upgrade from [vagrant-vanilla-k8s](https://github.com/gek0/vagrant-vanilla-k8s) repository
    - using Lima-VM with tested configuration for MacOS (ARM) and latest k8s and its components

## Lima-VM part
- follow the README.md in `node-definitions` directory
  - by default 3 (three) Worker nodes will be provisioned with 1 (one) Master node
  - `master-provision.sh` is used to configure the control-plane node and `worker-provision.sh` for worker Nodes
  - **master-node** has needed tools + some additional testing/debugging tools and binaries for administrative work
  - adapt node/VM resources to your usage but be careful of needed minimum requirements (depending on the installed components)

## Scripts and configuration part
- connect to **master-node** using `limactl shell master-1`
  - copy the node command give on the console
- connect to **worker-nodes[*]** using `limactl shell worker-X` command and paste/apply the command from previous step
- run `sudo -i` and inside /root/k8s/ directory run `./scripts/configure-cluster.sh`
  - this will configure Admin user for cluster, install all needed components, and merge the kubeconfig locally:
    - Calico CNI
    - Metrics Server
    - Istio ingress + istioctl
    - MetalLB (L2 mode, IP pool `192.168.104.50-70`)
    - Local Path Provisioner (dynamic PV provisioning via node local filesystem)
    - Monitoring stack (Prometheus, Grafana, Loki + Promtail, Alertmanager)
  - at the end it calls `scripts/converge-kube-config.sh` automatically to merge the cluster admin kubeconfig into `~/.kube/config`
- [OPTIONAL]: re-run `k8s/scripts/converge-kube-config.sh` standalone at any time to re-merge the kubeconfig
  - `k9s` and `kubectl` are also installed in **master-node** so cluster can be configured from there directly
- join worker Nodes using the token provided with first script

## K8s part
- use manifests in `k8s/manifests` directory per your liking, everything provided as learning examples

## Exposed Services

All user-facing services are exposed via MetalLB from the pool `192.168.104.50-70`:

| Component              | Address                       | Credentials / Notes                                              |
|------------------------|-------------------------------|------------------------------------------------------------------|
| Istio Ingress Gateway  | http://192.168.104.50         | Routes `*.local.io` hosts — wire via VirtualService              |
| ArgoCD                 | http://192.168.104.52         | admin / run `patch-argocd-service.sh` to print initial password  |
| Vault                  | http://192.168.104.53:8200    | See `k8s/manifests/hashicorp-vault/README.md`                    |
| Grafana                | http://192.168.104.54         | admin / admin — Prometheus & Loki datasources pre-configured     |

Prometheus and Alertmanager are ClusterIP only — accessible through Grafana or via `kubectl port-forward`.

## Host part
- use `port-forward.sh` script on your host to access a k8s service via SSH tunnel from your Mac browser
  - usage: `./port-forward.sh <host_port:node_port/protocol>` (e.g. `./port-forward.sh 80:30718/TCP`)
  - privileged ports (< 1024) are automatically remapped to `port + 8000` to avoid macOS restrictions (e.g. port 80 → localhost:8080)
