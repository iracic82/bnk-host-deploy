#!/usr/bin/env bash
# Installs F5 BIG-IP Next for Kubernetes (BNK) in Host mode on a self-managed cluster, following
# F5's "Install BNK (Host) on a self-managed cluster using FLO" guide, one phase per guide step.
#
# Usage:
#   ./install.sh --cluster clusters/lab.yaml            install the cluster a file describes
#   ./install.sh --cluster clusters/lab.yaml --plan     server-side dry run, changes nothing
#   ./install.sh --cluster clusters/lab.yaml --phase 30 run one phase
#   ./install.sh --env lab                              no cluster file: current kubectl context
#   ./install.sh --list-phases                          what each phase does, and the doc step
#
# Configuration is layered, later wins:
#   versions.env               what gets installed (every pinned version)
#   environments/<env>.env     policy: sizing, strictness, timeouts, licence rules
#   clusters/<name>.yaml       where: context, TMM node, storage class (picks the environment)
#   profiles/host.env          the deployment model
#
# Secrets come from the process environment only, never from git:
#   FAR_PULL_JSON     path to the F5 Artifact Registry service-account key (cne_pull_64.json)
#   BNK_LICENSE_JWT   the licence token (or BNK_LICENSE_FILE, a path to it)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS="https://clouddocs.f5.com/bigip-next-for-kubernetes/latest/install/bnk-host-self-managed-flo"

# id : title : the F5 guide step it automates
PHASES=(
  "00-preflight:Preflight checks:prepare-your-computer-and-cluster/system-requirements.html"
  "05-nodes:Label the TMM node:prepare-your-computer-and-cluster/label-tmm-nodes.html"
  "10-prereqs:Cluster prerequisites (Multus, cert-manager, CA issuer):prepare-your-computer-and-cluster/install-and-configure-open-source-cert-manager.html"
  "20-registry:Registry auth, namespaces, pull secrets:prepare-to-install/create-a-pull-secret-manifest-for-f5-artifact-registry.html"
  "30-flo:F5 Lifecycle Operator:install/prepare-the-cne-core-and-install-flo.html"
  "40-certs:CWC and OTEL certificates:install/prepare-the-cne-core-and-install-flo.html"
  "45-attachments:TMM data-plane attachments (Multus NADs):install/install-a-cne-instance-using-flo.html"
  "50-cneinstance:CNEInstance:install/install-a-cne-instance-using-flo.html"
  "55-network:TMM network (VLANs, self IPs, VIP pool, GatewayClass):install/install-a-cne-instance-using-flo.html"
  "60-license:Licence:install/license-your-cluster-flo.html"
  "65-ready:Wait for the data plane:install/install-a-cne-instance-using-flo.html"
  "70-verify:Verification:install/license-your-cluster-flo.html"
)

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; }

CLUSTER_FILE=""; BNK_ENV=""; ONLY_PHASE=""; SKIP_LICENSE=0; DRY_RUN=0
KUBE_CONTEXT="${KUBE_CONTEXT:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster) CLUSTER_FILE="$2"; shift 2 ;;
    --env) BNK_ENV="$2"; shift 2 ;;
    --phase) ONLY_PHASE="$2"; shift 2 ;;
    --plan|--dry-run) DRY_RUN=1; shift ;;
    --skip-license) SKIP_LICENSE=1; shift ;;
    --context) KUBE_CONTEXT="$2"; shift 2 ;;
    --list-phases)
      for e in "${PHASES[@]}"; do IFS=: read -r id t d <<<"$e"; printf '%-16s %-52s %s/%s\n' "$id" "$t" "$DOCS" "$d"; done
      exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown flag $1 (try --help)"; exit 2 ;;
  esac
done

# shellcheck source=versions.env
source "$HERE/versions.env"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
export HERE

if [[ -n "$CLUSTER_FILE" ]]; then
  # shellcheck source=lib/cluster.sh
  source "$HERE/lib/cluster.sh"
  load_cluster "$CLUSTER_FILE" || exit 2
  [[ -z "$BNK_ENV" || "$BNK_ENV" == "$CLUSTER_ENV" ]] \
    || { echo "--env $BNK_ENV contradicts $CLUSTER_FILE, which says environment: $CLUSTER_ENV"; exit 2; }
  BNK_ENV="$CLUSTER_ENV"
  if [[ "$CLUSTER_ENABLED" != "true" && "$DRY_RUN" == "0" ]]; then
    echo "$CLUSTER_FILE has enabled: false. Set it to true (in a pull request) to install."; exit 3
  fi
fi
[[ -n "$BNK_ENV" ]] || { echo "pass --cluster <file> or --env <name>"; exit 2; }
ENV_FILE="$HERE/environments/${BNK_ENV}.env"
[[ -r "$ENV_FILE" ]] || { echo "no environment at $ENV_FILE"; exit 2; }

# The cluster file's values must survive the environment file, so remember them and re-apply.
_keep=(KUBE_CONTEXT BNK_STORAGECLASS BNK_POD_CIDR BNK_DEPLOYMENT_SIZE)
declare -A _saved=()
for v in "${_keep[@]}"; do [[ -n "${!v:-}" ]] && _saved[$v]="${!v}"; done
# shellcheck disable=SC1090
source "$ENV_FILE"
for v in "${!_saved[@]}"; do printf -v "$v" '%s' "${_saved[$v]}"; done
# shellcheck source=profiles/host.env
source "$HERE/profiles/host.env"
PROFILE=host
# Extra legs only reach TMM's data plane when TMM maps them; declaring networks implies it.
[[ -n "${BNK_NETWORK_ATTACHMENTS:-}" ]] && BNK_TMM_MAPRES=true

# Licence from a file is the shape Forge and Instruqt hand it over in.
if [[ -z "${BNK_LICENSE_JWT:-}" && -n "${BNK_LICENSE_FILE:-}" && -r "${BNK_LICENSE_FILE}" ]]; then
  BNK_LICENSE_JWT="$(tr -d '\n\r ' < "$BNK_LICENSE_FILE")"
fi

export PROFILE SKIP_LICENSE DRY_RUN BNK_LICENSE_JWT
export BNK_ENV_NAME BNK_DEPLOYMENT_SIZE BNK_STORAGECLASS BNK_POD_CIDR BNK_TMM_MTU BNK_LICENSE_MODE
export BNK_DYNAMIC_ROUTING BNK_CORE_COLLECTION BNK_PROFILE_NAME BNK_DPU_ENABLED BNK_NETWORK_ATTACHMENTS
export BNK_ZEBOS_STATE BNK_NEEDS_HUGEPAGES BNK_NEEDS_SRIOV
export BNK_TMM_NODES="${BNK_TMM_NODES:-}" BNK_TMM_MANAGE_LABELS="${BNK_TMM_MANAGE_LABELS:-false}"
export BNK_WATCH_NAMESPACES="${BNK_WATCH_NAMESPACES:-}" BNK_TMM_MAPRES="${BNK_TMM_MAPRES:-false}"
export BNK_LEGACY_NETWORK="${BNK_LEGACY_NETWORK:-false}" CLUSTER_ATTACHMENTS="${CLUSTER_ATTACHMENTS:-}" CLUSTER_NETWORK="${CLUSTER_NETWORK:-}"
export BNK_REQUIRE_LICENSE="${BNK_REQUIRE_LICENSE:-true}" BNK_STRICT_PREFLIGHT="${BNK_STRICT_PREFLIGHT:-false}"
export BNK_WAIT_TIMEOUT="${BNK_WAIT_TIMEOUT:-1800}"

# In a pod (the Argo CD install Job) kubectl uses the pod's service account; there are no contexts.
[[ "${BNK_IN_CLUSTER:-false}" == "true" ]] && KUBE_CONTEXT=""
if [[ -n "$KUBE_CONTEXT" ]]; then
  kubectl config use-context "$KUBE_CONTEXT" >/dev/null 2>&1 || { echo "no kubectl context named $KUBE_CONTEXT"; exit 2; }
fi

banner "BNK ${BNK_VERSION} host  env=${BNK_ENV_NAME}  cluster=${CLUSTER_NAME:-$(kubectl config current-context 2>/dev/null || echo '?')}$([[ $DRY_RUN == 1 ]] && echo '  [plan: nothing will change]')$([[ $SKIP_LICENSE == 1 ]] && echo '  [unlicensed]')"

for entry in "${PHASES[@]}"; do
  IFS=: read -r id title doc <<<"$entry"; num="${id%%-*}"
  [[ -n "$ONLY_PHASE" && "$num" != "$ONLY_PHASE" ]] && continue
  if [[ "$SKIP_LICENSE" == "1" && "$num" == "60" ]]; then
    log "$title"
    [[ "$BNK_REQUIRE_LICENSE" == "true" ]] && die "--skip-license refused: ${BNK_ENV_NAME} sets BNK_REQUIRE_LICENSE=true"
    warn "skipped, unlicensed run"; continue
  fi
  log "$title"
  docref "$DOCS/$doc"
  phase_begin "$id" "$title" "$DOCS/$doc"
  # shellcheck disable=SC1090
  source "$HERE/lib/${id}.sh"
  phase_end
done

# Provenance on a full install, or when an orchestrator that runs phase by phase (Forge) asks for it
# on its last step. The nightly drift job runs phase 70 alone and must not re-stamp the cluster.
if [[ "$DRY_RUN" == "0" && ( -z "$ONLY_PHASE" || "${BNK_RECORD_PROVENANCE:-false}" == "true" ) ]]; then record_provenance; fi
log "Done  env=${BNK_ENV_NAME}  BNK ${BNK_VERSION}"
