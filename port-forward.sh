#!/usr/bin/env bash
# Forwards k8s LoadBalancer services from the Lima master node to the local host via SSH tunnel.
#
# Usage:
#   ./port-forward.sh                             - auto-discover and forward all LoadBalancer services
#   ./port-forward.sh <host_port:node_port/proto> - forward a single service (e.g. 80:30718/TCP)
#
# Privileged ports (< 1024) are automatically remapped to port+8000 on the local host.
# Conflicting local ports are resolved by incrementing by 1 until a free port is found.

set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib.sh"

NODE="master-1"
NODE_SSH_PORT=$(limactl list | grep "$NODE" | awk -F ' ' '{ print $3 }' | awk -F ':' '{ print $2 }')

_used_ports=()
_free_port=0

remap_port() {
  local port=$1
  if [[ "$port" -lt 1024 ]]
  then
    echo $((port + 8000))
  else
    echo "$port"
  fi
}

# Sets _free_port — must NOT be called in a subshell or _used_ports tracking breaks
find_free_port() {
  local port=$1
  while lsof -i :"$port" -t &>/dev/null || [[ " ${_used_ports[*]} " == *" $port "* ]]
  do
    echo -e "${YELLOW}[WAIT]${RESET}  Port $port is already in use — trying $((port + 1))" >&2
    port=$((port + 1))
  done
  _used_ports+=("$port")
  _free_port=$port
}

forward_single() {
  local input="$1"
  local input_no_proto=${input%%/*}
  local TARGET_HOST_PORT=${input_no_proto%%:*}
  local SERVICE_PORT=${input_no_proto##*:}
  local remapped

  remapped=$(remap_port "$TARGET_HOST_PORT")

  if [[ "$remapped" != "$TARGET_HOST_PORT" ]]
  then
    warn "Port $TARGET_HOST_PORT is privileged on macOS — using $remapped as local port instead"
  fi

  find_free_port "$remapped"
  local LOCAL_PORT=$_free_port

  info "Forwarding localhost:$LOCAL_PORT -> $NODE:$SERVICE_PORT ..."
  info "Open http://localhost:$LOCAL_PORT to access the service"
  info "Press Ctrl+C to stop"

  local ssh_pid
  ssh -L "$LOCAL_PORT":localhost:"$SERVICE_PORT" -N -l root -p "$NODE_SSH_PORT" \
    -o ExitOnForwardFailure=yes 127.0.0.1 &
  ssh_pid=$!

  trap 'kill "$ssh_pid" 2>/dev/null; ok "Tunnel stopped"; exit 0' SIGINT SIGTERM
  wait "$ssh_pid"
}

forward_all() {
  section "Discovering LoadBalancer services"
  info "Querying services on $NODE ..."

  # Kill any stale tunnels from previous runs to this node
  pkill -f "ssh.*${NODE_SSH_PORT}.*127.0.0.1" 2>/dev/null || true

  local raw
  raw=$(ssh -p "$NODE_SSH_PORT" -l root -o LogLevel=QUIET 127.0.0.1 \
    'kubectl --kubeconfig=/etc/kubernetes/admin.conf get svc --all-namespaces -o go-template='"'"'{{range .items}}{{if eq .spec.type "LoadBalancer"}}{{.metadata.name}}{{"\t"}}{{.metadata.namespace}}{{"\t"}}{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}{{"\t"}}{{range .spec.ports}}{{.port}}:{{.nodePort}}/{{.protocol}} {{end}}{{"\n"}}{{end}}{{end}}'"'"'')

  if [[ -z "$raw" ]]
  then
    warn "No LoadBalancer services found on $NODE"
    exit 0
  fi

  section "Starting port forwards"

  local pids=()
  local summary=()
  local name namespace external_ip ports_str svc_port nodeport proto

  while IFS=$'\t' read -r name namespace external_ip ports_str
  do
    [[ -z "$name" ]] && continue
    [[ "$name" == "istio-ingressgateway" ]] && continue
    for port_proto in $ports_str
    do
      svc_port=${port_proto%%:*}
      nodeport=${port_proto##*:}
      nodeport=${nodeport%%/*}
      proto=${port_proto##*/}
      find_free_port "$(remap_port "$svc_port")"
      local local_port=$_free_port
      info "Starting tunnel: ${name} (${namespace}) [${proto}]"
      ssh -L "${local_port}":localhost:"${nodeport}" -N -l root -p "$NODE_SSH_PORT" \
        -o LogLevel=QUIET 127.0.0.1 &
      pids+=($!)
      summary+=("${name}|${namespace}|${proto}|${local_port}|${svc_port}")
    done
  done <<< "$raw"

  section "Active tunnels"
  for entry in "${summary[@]}"
  do
    IFS='|' read -r svc_name svc_ns svc_proto local_p orig_p <<< "$entry"
    printf "  ${CYAN}%-40s${RESET} ${GREEN}http://localhost:%-6s${RESET}  ${BOLD}%-6s${RESET}  ${YELLOW}(svc port: %s)${RESET}\n" \
      "${svc_name} (${svc_ns})" "${local_p}" "${svc_proto}" "${orig_p}"
  done

  echo
  ok "${#pids[@]} tunnel(s) active — press Ctrl+C to stop all"

  cleanup() {
    echo
    info "Stopping all tunnels ..."
    kill "${pids[@]}" 2>/dev/null || true
    ok "All tunnels stopped"
    exit 0
  }

  trap cleanup SIGINT SIGTERM
  wait "${pids[@]}" 2>/dev/null || true
}

if [[ -n "$1" ]]
then
  forward_single "$1"
else
  forward_all
fi
