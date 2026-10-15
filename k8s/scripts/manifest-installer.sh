#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"
DELETE_MODE=false

if [[ "$1" == "--delete" ]]
then
  DELETE_MODE=true
fi

# Collect service directories
services=()
while IFS= read -r dir
do
  services+=("$(basename "$dir")")
done < <(find "$MANIFESTS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

if [[ ${#services[@]} -eq 0 ]]
then
  warn "No service directories found in ${MANIFESTS_DIR}"
  exit 1
fi

section "Manifest Installer"
info "Available services:"
echo

PS3=$'\n> '
select service in "${services[@]}" "Quit"
do
  [[ "$service" == "Quit" ]] && info "Exiting" && exit 0
  [[ -n "$service" ]] && break
  warn "Invalid selection — try again"
done

SERVICE_DIR="${MANIFESTS_DIR}/${service}"

if [[ "$DELETE_MODE" == true ]]
then
  section "Deleting ${service}"
  warn "This will delete all resources for ${service}. Press enter to confirm or Ctrl+C to abort ..."
  read

  # Delete non-namespace resources first (reverse order), namespace last
  while IFS= read -r yaml
  do
    info "Deleting $(basename "$yaml") ..."
    kubectl delete --ignore-not-found -f "$yaml"
  done < <(find "$SERVICE_DIR" -maxdepth 1 -name "*.yaml" ! -name "namespace.yaml" | sort -r)

  if [[ -f "${SERVICE_DIR}/namespace.yaml" ]]
  then
    info "Deleting namespace ..."
    kubectl delete --ignore-not-found -f "${SERVICE_DIR}/namespace.yaml"
  fi

  ok "${service} resources deleted"
  exit 0
fi

section "Installing ${service}"

# namespace.yaml always first
if [[ -f "${SERVICE_DIR}/namespace.yaml" ]]
then
  info "Applying namespace ..."
  kubectl apply --server-side -f "${SERVICE_DIR}/namespace.yaml"
fi

# Apply remaining yamls
while IFS= read -r yaml
do
  info "Applying $(basename "$yaml") ..."
  kubectl apply --server-side -f "$yaml"
done < <(find "$SERVICE_DIR" -maxdepth 1 -name "*.yaml" ! -name "namespace.yaml" | sort)

ok "${service} manifests applied"

# Run patch-service.sh if present
if [[ -f "${SERVICE_DIR}/patch-service.sh" ]]
then
  if [[ -f "${SERVICE_DIR}/wait-for" ]]
  then
    section "Waiting for ${service} to be ready"
    while IFS=' ' read -r resource namespace
    do
      [[ -z "$resource" || "$resource" =~ ^# ]] && continue
      resource_type=${resource%%/*}
      resource_name=${resource##*/}
      info "Waiting for ${resource} in namespace ${namespace} ..."
      case "$resource_type" in
        deployment|statefulset|daemonset)
          kubectl rollout status "${resource}" -n "${namespace}" --timeout=120s
          ;;
        *)
          until kubectl get "${resource_type}" "${resource_name}" -n "${namespace}" &>/dev/null
          do
            warn "${resource} not yet available — retrying in 5s ..."
            sleep 5
          done
          ;;
      esac
      ok "${resource} is ready"
    done < "${SERVICE_DIR}/wait-for"
  else
    warn "No wait-for file found — waiting 15s before patching ..."
    sleep 15
  fi
  section "Patching ${service}"
  bash "${SERVICE_DIR}/patch-service.sh"
fi

ok "${service} installation complete"
