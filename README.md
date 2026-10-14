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
- run `sudo -i` and inside /root/k8s/ directory run `./create-cluster-admin.sh`
  - this will configure Admin user for cluster and install all needed components
    - Calico CNI
    - Metrics Server
    - Istio ingress + istioctl
    - MetalLB
- [OPTIONAL]: if you'd like to manage the cluster from host using your tools run `./converge-kube-config.sh` to update local ./kube/config file
  - `k9s` and `kubectl` are also installed in **master-node** so cluster can be configured from there directly
- join worker Nodes using the token provided with first script

## K8s part
- use manifests in `k8s/manifests` directory per your liking, everything provided as learning examples

## Host part
- use `port-forward.sh` script on your host to access LoadBalancer configured k8s service to access it in your host browser
