#!/usr/bin/env bash
set -e -o pipefail

if [[ -z "$1" ]]
then
  echo "Incorrect script usage"
  echo "Usage: $0 <host_port:service_port/protocol>"
  echo "Example: $0 80:31596/TCP"
  exit 1
fi

input="$1"
input_no_proto=${input%%/*}
TARGET_HOST_PORT=${input_no_proto%%:*}
SERVICE_PORT=${input_no_proto##*:}
NODE="master-1"

echo "Starting port forwarding from localhost:$TARGET_HOST_PORT to service port $SERVICE_PORT on the $NODE node..."
echo "Open http://localhost:$TARGET_HOST_PORT to access the forwarded service."
echo "Press Ctrl+C to stop port forwarding."
ssh -L "$TARGET_HOST_PORT":localhost:"$SERVICE_PORT" -N -l root -p $(limactl list | grep $NODE | awk -F ' ' '{ print $3 }' | awk -F ':' '{ print $2 }') 127.0.0.1
