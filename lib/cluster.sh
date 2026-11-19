# shellcheck shell=bash
# Loads clusters/<name>.yaml into the environment the phases read, and refuses a file that would
# produce a broken install. Sourced by install.sh and by the CI workflows, so a pull request is
# validated by exactly the code that will later apply it.
#
# The cluster file answers "where, and on which nodes". Versions live in versions.env, policy in
# environments/*.env. Keeping the three apart is what lets one pull request say one thing.

cluster_field() {  # cluster_field <file> <yq-path> [default]
  local v
  v="$(yq -r "$2 // \"\"" "$1" 2>/dev/null)" || v=""
  [[ "$v" == "null" ]] && v=""
  printf '%s' "${v:-${3:-}}"
}

# load_cluster <file>: exports the cluster's settings, fails with a reason on anything invalid.
load_cluster() {
  local f="$1" here="${HERE:-.}" name base
  command -v yq >/dev/null 2>&1 || { echo "yq is required to read cluster files" >&2; return 2; }
  [[ -r "$f" ]] || { echo "no cluster file at $f" >&2; return 2; }
  yq -e '.' "$f" >/dev/null 2>&1 || { echo "$f is not valid YAML" >&2; return 2; }

  base="$(basename "$f" .yaml)"
  name="$(cluster_field "$f" .name)"
  [[ "$name" == "$base" ]] || { echo "$f: name '$name' must match the file name '$base'" >&2; return 2; }

  CLUSTER_NAME="$name"
  CLUSTER_ENABLED="$(cluster_field "$f" .enabled false)"
  CLUSTER_ENV="$(cluster_field "$f" .environment)"
  KUBE_CONTEXT="${KUBE_CONTEXT:-$(cluster_field "$f" .kube_context)}"
  BNK_STORAGECLASS="$(cluster_field "$f" .storage_class "${BNK_STORAGECLASS:-}")"
  BNK_POD_CIDR="$(cluster_field "$f" .pod_cidr "${BNK_POD_CIDR:-}")"
  BNK_DEPLOYMENT_SIZE="$(cluster_field "$f" .deployment_size "${BNK_DEPLOYMENT_SIZE:-}")"
  BNK_TMM_NODES="$(yq -r '(.tmm.nodes // []) | join(",")' "$f")"
  BNK_TMM_MANAGE_LABELS="$(cluster_field "$f" .tmm.manage_labels false)"
  BNK_WATCH_NAMESPACES="$(yq -r '(.watch_namespaces // []) | join(",")' "$f")"
  # TMM's data-plane legs, in TMM interface order (1.1, 1.2, ...). Each is a NetworkAttachmentDefinition
  # in <name>.attachments.yaml next to this file. None: TMM has only its pod interface.
  BNK_NETWORK_ATTACHMENTS="$(yq -r '(.tmm.networks // []) | join(",")' "$f")"
  # AI inference: namespaces where BNK's controller may run F5 Endpoint Pickers (F5EPP). Phase 47
  # prepares them (InferencePool CRDs, namespace, pull secret), phase 50 names them on the CNEInstance.
  BNK_EPP_NAMESPACES="$(yq -r '(.inference.epp_namespaces // []) | join(",")' "$f")"
  local _ns
  for _ns in ${BNK_EPP_NAMESPACES//,/ }; do
    [[ "$_ns" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ && ${#_ns} -le 63 ]] \
      || { echo "$f: inference.epp_namespaces: '$_ns' is not a valid namespace name" >&2; return 2; }
    case "$_ns" in kube-*|f5-*|default|cert-manager|bnk-installer|argocd)
      echo "$f: inference.epp_namespaces: '$_ns' is a platform namespace, use one of your own (e.g. inference)" >&2; return 2 ;;
    esac
  done
  # pseudoCNI steers pod traffic through TMM except for these ranges (pods, services, node network, VIPs).
  BNK_POD_CIDR="$(yq -r '([.pod_cidr] + (.pseudo_cni_exclude // [])) | map(select(. != null)) | join(",")' "$f")"
  [[ -n "$BNK_POD_CIDR" ]] || BNK_POD_CIDR="192.168.0.0/16"
  # Optional companions, by convention next to the cluster file:
  #   <name>.attachments.yaml  NADs for tmm.networks, applied before the CNEInstance (phase 45)
  #   <name>.network.yaml      TMM VLANs, self IPs, VIP pool, GatewayClass, applied after it (phase 55)
  # true: TMM networking with F5SPKVlan + F5BnkGateway (the controller runs with USE_GATEWAY_SETTINGS=false)
  BNK_LEGACY_NETWORK="$(cluster_field "$f" .legacy_network_model false)"
  CLUSTER_DIR="$(cd "$(dirname "$f")" && pwd)"
  CLUSTER_ATTACHMENTS="$CLUSTER_DIR/${name}.attachments.yaml"; [[ -r "$CLUSTER_ATTACHMENTS" ]] || CLUSTER_ATTACHMENTS=""
  CLUSTER_NETWORK="$CLUSTER_DIR/${name}.network.yaml";         [[ -r "$CLUSTER_NETWORK" ]] || CLUSTER_NETWORK=""
  if [[ -n "$BNK_NETWORK_ATTACHMENTS" && -z "$CLUSTER_ATTACHMENTS" ]]; then
    echo "$f: tmm.networks is set but ${name}.attachments.yaml (the NADs) is missing" >&2; return 2
  fi

  [[ -n "$CLUSTER_ENV" ]] || { echo "$f: environment is required" >&2; return 2; }
  [[ -r "$here/environments/${CLUSTER_ENV}.env" ]] \
    || { echo "$f: environment '$CLUSTER_ENV' has no environments/${CLUSTER_ENV}.env" >&2; return 2; }
  case "$CLUSTER_ENABLED" in true|false) ;; *) echo "$f: enabled must be true or false" >&2; return 2 ;; esac
  case "$BNK_TMM_MANAGE_LABELS" in true|false) ;; *) echo "$f: tmm.manage_labels must be true or false" >&2; return 2 ;; esac

  # An enabled cluster must say where TMM runs. Without a labelled node the operator never schedules
  # TMM, and the failure it shows is a panic deep in the operator, not a message about labels.
  if [[ "$CLUSTER_ENABLED" == "true" && -z "$BNK_TMM_NODES" ]]; then
    echo "$f: enabled clusters must list tmm.nodes (the node TMM runs on, see 'kubectl get nodes')" >&2
    return 2
  fi
  if [[ "$BNK_TMM_NODES" == *,* ]]; then
    echo "$f: tmm.nodes lists more than one node. BNK host mode runs one TMM per labelled node, and" >&2
    echo "    this repository is qualified with exactly one. Name a single node." >&2
    return 2
  fi

  export CLUSTER_NAME CLUSTER_ENABLED CLUSTER_ENV KUBE_CONTEXT BNK_STORAGECLASS BNK_POD_CIDR \
         BNK_DEPLOYMENT_SIZE BNK_TMM_NODES BNK_TMM_MANAGE_LABELS BNK_WATCH_NAMESPACES \
         BNK_NETWORK_ATTACHMENTS CLUSTER_ATTACHMENTS CLUSTER_NETWORK BNK_LEGACY_NETWORK BNK_EPP_NAMESPACES
}
