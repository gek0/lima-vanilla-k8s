#!/usr/bin/env bash
set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
nodeIP=$(echo $(hostname -I | tr "." "-"))
nodeIPclean=$(hostname -I)
k8sMajorVersion="1.37"
podNetworkCIDR="10.244.0.0/16"

# Set hostname and prompt
sudo hostnamectl set-hostname "master-node-$nodeIP"
echo "master-node-$nodeIP" | sudo tee /etc/hostname
echo "export PS1=\"\[\e[1;35m\]\u\[\033[m\]@\[\e[1;92m\]master-node-$nodeIP\[\033[m\]:\w \$ \"" >> ~/.bashrc

# Disable swap
sudo swapoff -a
sudo sed -i 's/\/swap/#\/swap/g' /etc/fstab

# Load containerd modules
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# Kubernetes sysctl settings
sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

sleep 1

# Install dependencies
sudo apt-get update -y
sudo apt install -y curl gpg gnupg2 software-properties-common apt-transport-https ca-certificates

# Install Helm (latest)
HELM_BUILDKITE_APT_KEY_ID="DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6"
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey > "${TMPDIR:-/tmp}/helm.gpg"
# Ensure that the key ID matches to prevent a repository compromise from establishing an attacker controlled key
if [ "$(gpg --show-keys --with-colons "${TMPDIR:-/tmp}/helm.gpg" | awk -F: '$1 == "fpr" {print $10}' | head -n 1)" != "${HELM_BUILDKITE_APT_KEY_ID}" ]; then echo "ERROR: Unexpected Helm APT key ID: potential key compromise"; exit 1; fi
cat "${TMPDIR:-/tmp}/helm.gpg" | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install -y helm

# Install containerd (from Ubuntu repo)
sudo apt-get install -y containerd

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Add Kubernetes repo (latest stable)
sudo mkdir -p /etc/apt/keyrings
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${k8sMajorVersion}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${k8sMajorVersion}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

sudo apt-get update
sudo apt install -y kubelet kubeadm kubectl net-tools siege etcd-client
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

# Initialize Kubernetes master
sudo kubeadm init --apiserver-advertise-address=${nodeIPclean} --control-plane-endpoint=${nodeIPclean} --pod-network-cidr=${podNetworkCIDR}

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown "$(id -u):$(id -g)" $HOME/.kube/config

# Set MOTD
chmod +x "$SCRIPT_DIR/master-motd.sh"
bash "$SCRIPT_DIR/master-motd.sh"

# Allow standard SSH access from host
chmod +x "$SCRIPT_DIR/host-ssh-standard-access.sh"
bash "$SCRIPT_DIR/host-ssh-standard-access.sh"

echo -e 'alias ku="kubectl"\ncomplete -F __start_kubectl ku' >> ~/.bashrc

# Install k9s (latest)
cd /tmp
curl -Lo k9s_linux_arm64.deb https://github.com/derailed/k9s/releases/download/v0.51.0/k9s_linux_arm64.deb
sudo dpkg -i k9s_linux_arm64.deb

echo "I'm ready and installed!"
