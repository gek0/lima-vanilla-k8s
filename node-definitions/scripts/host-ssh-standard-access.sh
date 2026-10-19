#!/usr/bin/env bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

SSH_FILE="/root/.ssh/authorized_keys"

info "Adding host public key to ${SSH_FILE} ..."
cat /mnt/ssh/id_rsa.pub | sudo tee -a "${SSH_FILE}" > /dev/null
ok "Host SSH access configured"
