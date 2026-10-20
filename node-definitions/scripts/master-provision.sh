#!/usr/bin/env bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
nodeIP=$(echo $(hostname -I | tr "." "-"))
nodeIPclean=$(hostname -I)
k8sMajorVersion="1.37"
podNetworkCIDR="10.244.0.0/16"

section "Node Setup"
info "Setting hostname to master-node-$nodeIP ..."
sudo hostnamectl set-hostname "master-node-$nodeIP"
echo "master-node-$nodeIP" | sudo tee /etc/hostname
cat >> ~/.bashrc << 'BASHRC'

kube_ctx() {
  local ctx ns
  ctx=$(kubectl config current-context 2>/dev/null) || return
  ns=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null)
  echo "(${ctx}:${ns:-default})"
}
BASHRC
echo "export PS1=\"\[\e[1;35m\]\u\[\033[m\]@\[\e[1;92m\]master-node-$nodeIP\[\033[m\]:\w \[\e[0;36m\]\\\$(kube_ctx)\[\033[m\] \$ \"" >> ~/.bashrc
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
sudo apt install -y curl gpg gnupg2 software-properties-common apt-transport-https ca-certificates
ok "Base packages installed"

section "Helm"
info "Verifying Helm APT key ..."
HELM_BUILDKITE_APT_KEY_ID="DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6"
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey > "${TMPDIR:-/tmp}/helm.gpg"
if [ "$(gpg --show-keys --with-colons "${TMPDIR:-/tmp}/helm.gpg" | awk -F: '$1 == "fpr" {print $10}' | head -n 1)" != "${HELM_BUILDKITE_APT_KEY_ID}" ]
then
  echo "ERROR: Unexpected Helm APT key ID: potential key compromise"
  exit 1
fi
cat "${TMPDIR:-/tmp}/helm.gpg" | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install -y helm
ok "Helm installed"

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
sudo apt install -y kubelet kubeadm kubectl net-tools siege etcd-client
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
ok "Kubernetes components installed"

section "Cluster Init"
info "Running kubeadm init ..."
sudo kubeadm init --apiserver-advertise-address=${nodeIPclean} --control-plane-endpoint=${nodeIPclean} --pod-network-cidr=${podNetworkCIDR}
info "Configuring kubeconfig for root ..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown "$(id -u):$(id -g)" $HOME/.kube/config
echo -e 'source <(kubectl completion bash)\nalias ku="kubectl"\ncomplete -F __start_kubectl ku' >> ~/.bashrc
ok "Cluster initialised"

section "MOTD + SSH Access"
chmod +x "$SCRIPT_DIR/master-motd.sh"
bash "$SCRIPT_DIR/master-motd.sh"
chmod +x "$SCRIPT_DIR/host-ssh-standard-access.sh"
bash "$SCRIPT_DIR/host-ssh-standard-access.sh"
ok "MOTD and SSH access configured"

section "Tools"
cd /tmp

info "Installing k9s ..."
curl -Lso k9s_linux_arm64.deb https://github.com/derailed/k9s/releases/download/v0.51.0/k9s_linux_arm64.deb
sudo dpkg -i k9s_linux_arm64.deb
ok "k9s installed"

info "Installing kubectx and kubens ..."
curl -Lso kubectx.tar.gz https://github.com/ahmetb/kubectx/releases/download/v0.11.0/kubectx_v0.11.0_linux_arm64.tar.gz
curl -Lso kubens.tar.gz https://github.com/ahmetb/kubectx/releases/download/v0.11.0/kubens_v0.11.0_linux_arm64.tar.gz
tar -xzf kubectx.tar.gz kubectx && sudo mv kubectx /usr/local/bin/
tar -xzf kubens.tar.gz kubens   && sudo mv kubens  /usr/local/bin/
rm -f kubectx.tar.gz kubens.tar.gz
ok "kubectx and kubens installed"

info "Installing ArgoCD CLI ..."
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-arm64
sudo install -m 555 argocd /usr/local/bin/argocd
rm -f argocd
ok "ArgoCD CLI installed"

info "Installing Terraform ..."
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update
sudo apt-get install -y terraform
ok "Terraform installed"

section "Done"
ok "Master node provisioned and ready!"
