#!/usr/bin/env bash
set -e -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/k8s/scripts/lib.sh"

if [[ -z "$1" ]]; then
  echo "Usage: $0 <host_port:service_port/protocol>"
  echo "Example: $0 80:31596/TCP"
  exit 1
fi

input="$1"
input_no_proto=${input%%/*}
TARGET_HOST_PORT=${input_no_proto%%:*}
SERVICE_PORT=${input_no_proto##*:}
NODE="master-1"

if [[ "$TARGET_HOST_PORT" -lt 1024 ]]; then
  LOCAL_PORT=$((TARGET_HOST_PORT + 8000))
  warn "Port $TARGET_HOST_PORT is privileged on macOS — using $LOCAL_PORT as local port instead"
else
  LOCAL_PORT=$TARGET_HOST_PORT
fi

NODE_SSH_PORT=$(limactl list | grep "$NODE" | awk -F ' ' '{ print $3 }' | awk -F ':' '{ print $2 }')

info "Forwarding localhost:$LOCAL_PORT -> $NODE:$SERVICE_PORT ..."
info "Open http://localhost:$LOCAL_PORT to access the service"
info "Press Ctrl+C to stop"

ssh -L "$LOCAL_PORT":localhost:"$SERVICE_PORT" -N -l root -p "$NODE_SSH_PORT" 127.0.0.1
