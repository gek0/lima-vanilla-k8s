#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

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
select service in "${services[@]}" "exit"
do
  [[ "$service" == "exit" ]] && info "Exiting" && exit 0
  [[ -n "$service" ]] && break
  warn "Invalid selection — try again"
done

SERVICE_DIR="${MANIFESTS_DIR}/${service}"

# Support services that keep install files in a nested install/ subdirectory
# (e.g. a service stored as a subrepo with install/ inside it).
# Falls back to SERVICE_DIR if no nested install/ is found.
INSTALL_DIR="${SERVICE_DIR}"
if ! find "${SERVICE_DIR}" -maxdepth 1 -name "*.yaml" | grep -q .
then
  found=$(find "${SERVICE_DIR}" -mindepth 2 -maxdepth 2 -type d -name "install" | head -1)
  if [[ -n "$found" ]]
  then
    INSTALL_DIR="$found"
  fi
fi

# wait-for lives alongside the other install files (in INSTALL_DIR or service root)
WAIT_FOR_FILE="${INSTALL_DIR}/wait-for"

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
  done < <(find "$INSTALL_DIR" -maxdepth 1 -name "*.yaml" ! -name "namespace.yaml" | sort -r)

  if [[ -f "${INSTALL_DIR}/namespace.yaml" ]]
  then
    info "Deleting namespace ..."
    kubectl delete --ignore-not-found -f "${INSTALL_DIR}/namespace.yaml"
  fi

  ok "${service} resources deleted"
  exit 0
fi

# Run setup-requirements-service.sh before applying manifests if present
if [[ -f "${SERVICE_DIR}/setup-requirements-service.sh" ]]
then
  section "Setting up requirements for ${service}"
  bash "${SERVICE_DIR}/setup-requirements-service.sh"
fi

section "Installing ${service}"

# Prompt for target namespace — default read from namespace.yaml if present
DEFAULT_NAMESPACE=""
if [[ -f "${INSTALL_DIR}/namespace.yaml" ]]
then
  DEFAULT_NAMESPACE=$(awk '/^metadata:/{f=1} f && /^[[:space:]]+name:/{print $2; exit}' "${INSTALL_DIR}/namespace.yaml")
fi

if [[ -n "$DEFAULT_NAMESPACE" ]]
then
  read -r -p $'\e[36m[INFO]\e[0m  Target namespace ['"${DEFAULT_NAMESPACE}"']: ' SERVICE_NAMESPACE
  SERVICE_NAMESPACE="${SERVICE_NAMESPACE:-$DEFAULT_NAMESPACE}"
else
  read -r -p $'\e[36m[INFO]\e[0m  Target namespace: ' SERVICE_NAMESPACE
fi
info "Using namespace: ${SERVICE_NAMESPACE}"

# namespace.yaml always first (cluster-scoped — no -n flag)
if [[ -f "${INSTALL_DIR}/namespace.yaml" ]]
then
  info "Applying namespace ..."
  kubectl apply --server-side --force-conflicts -f "${INSTALL_DIR}/namespace.yaml"
fi

# install.yaml second — base install must precede any config overlays
if [[ -f "${INSTALL_DIR}/install.yaml" ]]
then
  info "Applying install.yaml ..."
  kubectl apply --server-side --force-conflicts -n "${SERVICE_NAMESPACE}" -f "${INSTALL_DIR}/install.yaml"
fi

# Apply remaining yamls — skip namespace, install, and Helm values files
while IFS= read -r yaml
do
  info "Applying $(basename "$yaml") ..."
  kubectl apply --server-side --force-conflicts -n "${SERVICE_NAMESPACE}" -f "$yaml"
done < <(find "$INSTALL_DIR" -maxdepth 1 -name "*.yaml" ! -name "namespace.yaml" ! -name "install.yaml" ! -name "*-values.yaml" | sort)

ok "${service} manifests applied"

# Run patch-service.sh if present
if [[ -f "${INSTALL_DIR}/patch-service.sh" ]]
then
  if [[ -f "${WAIT_FOR_FILE}" ]]
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
    done < "${WAIT_FOR_FILE}"
  else
    warn "No wait-for file found — waiting 15s before patching ..."
    sleep 15
  fi
  section "Patching ${service}"
  bash "${INSTALL_DIR}/patch-service.sh"
fi

ok "${service} installation complete"
