#!/usr/bin/env bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
nodeIP=$(echo $(hostname -I | tr "." "-"))
nodeIPclean=$(hostname -I)
k8sMajorVersion="1.37"

section "Node Setup"
info "Setting hostname to worker-node-$nodeIP ..."
sudo hostnamectl set-hostname "worker-node-$nodeIP"
echo "worker-node-$nodeIP" | sudo tee /etc/hostname
echo "export PS1=\"\[\e[1;35m\]\u\[\033[m\]@\[\e[1;92m\]worker-node-$nodeIP\[\033[m\]:\w \$ \"" >> ~/.bashrc
ok "Hostname and prompt configured"

section "System Configuration"
info "Disabling swap ..."
sudo swapoff -a
sudo sed -i 's/\/swap/#\/swap/g' /etc/fstab
ok "Swap disabled"

info "Loading containerd kernel modules ..."
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
ok "Kernel modules loaded"

info "Applying Kubernetes sysctl settings ..."
sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system
ok "sysctl settings applied"

sleep 1

section "Dependencies"
info "Installing base packages ..."
sudo apt-get update -y
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates
ok "Base packages installed"

section "containerd"
info "Installing containerd ..."
sudo apt-get install -y containerd
info "Configuring containerd with SystemdCgroup ..."
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
ok "containerd installed and configured"

section "Kubernetes"
info "Adding Kubernetes APT repository (v${k8sMajorVersion}) ..."
sudo mkdir -p /etc/apt/keyrings
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${k8sMajorVersion}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${k8sMajorVersion}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo apt-get update
info "Installing kubelet, kubeadm, kubectl ..."
sudo apt install -y kubelet kubeadm kubectl net-tools
sudo apt-mark hold kubelet kubeadm kubectl
ok "Kubernetes components installed"

section "SSH Access"
chmod +x "$SCRIPT_DIR/host-ssh-standard-access.sh"
bash "$SCRIPT_DIR/host-ssh-standard-access.sh"

section "Done"
ok "Worker node provisioned — run the kubeadm join command from the master to join the cluster"
