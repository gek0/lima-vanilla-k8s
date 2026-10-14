#!/usr/bin/env bash
set -e

SSH_FILE="/root/.ssh/authorized_keys"
HOST_PUBLIC_KEY="$(cat "/mnt/ssh/id_rsa.pub")"

echo "$HOST_PUBLIC_KEY" | sudo tee -a $SSH_FILE
