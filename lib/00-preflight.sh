# shellcheck shell=bash
# Preflight. Fails fast on the things that otherwise break the install twenty minutes later.
# Maps to the guide's "System requirements" and "Prepare your computer" pages.
_IN_PREFLIGHT=1

: "${FAR_PULL_JSON:?FAR_PULL_JSON must point at the F5 Artifact Registry key (cne_pull_64.json)}"
[[ -r "$FAR_PULL_JSON" ]] || die "cannot read $FAR_PULL_JSON"
# make and python3: F5's cert-gen drives openssl through a Makefile that calls python3 profile.py.
# Without either, gen_cert.sh still writes its yaml, empty, kubectl applies it happily, and the
# licence fails to validate three phases later ("make: [regen] Error 127" is python3 missing).
for c in kubectl helm jq openssl base64 tar make python3; do
  command -v "$c" >/dev/null || die "$c not on PATH"
done
ok "tooling present: kubectl $(kubectl version --client -o json 2>/dev/null | sed -n 's/.*"gitVersion": *"\([^"]*\)".*/\1/p' | head -1), helm $(helm version --short 2>/dev/null)"

# Decide the licence now, not after phase 50 has spent its timeout waiting for something an
# unlicensed install can never reach. A plan never needs one.
if [[ "$DRY_RUN" == "0" && "$SKIP_LICENSE" == "0" && -z "${BNK_LICENSE_JWT:-}" ]]; then
  [[ "$BNK_REQUIRE_LICENSE" == "true" ]] && die "no BNK_LICENSE_JWT and ${BNK_ENV_NAME} requires a licence"
  warn "no BNK_LICENSE_JWT; ${BNK_ENV_NAME} allows that, continuing unlicensed"
  SKIP_LICENSE=1; export SKIP_LICENSE
fi

if ! _kv_err=$(kubectl version --request-timeout=15s 2>&1 >/dev/null); then
  printf '%s\n' "$_kv_err" | tail -3 | sed 's/^/        /' >&2
  die "no reachable cluster (KUBECONFIG=${KUBECONFIG:-in-cluster service account}, context=${KUBE_CONTEXT:-current})"
fi
minor=$(kubectl version -o json 2>/dev/null | sed -n 's/.*"minor": *"\([0-9]*\).*/\1/p' | tail -1)
ok "API server reachable: $(kubectl config current-context 2>/dev/null), Kubernetes 1.${minor}"
[[ "$minor" == "${K8S_MINOR#*.}" ]] || warn "Kubernetes 1.${minor}; BNK ${BNK_VERSION} host mode is qualified on ${K8S_MINOR}"

# CNI. FLO's own preflight blocks with an ERROR when it cannot place the CNI in a family it knows.
# Calico is the primary (and only tested) CNI for host mode on generic Kubernetes.
pods=$(kubectl get pods -A -o name 2>/dev/null || true)
case "$pods" in
  *calico*)   BNK_DETECTED_CNI=calico;  ok "CNI: Calico, the primary supported CNI" ;;
  *ovnkube*)  BNK_DETECTED_CNI=ovn-kubernetes; ok "CNI: OVN-Kubernetes (OpenShift)" ;;
  *flannel*)  BNK_DETECTED_CNI=flannel; warn "CNI: Flannel is recognised but untested; Calico is the one F5 tests" ;;
  *cilium*)   BNK_DETECTED_CNI=cilium;  warn "CNI: Cilium is not a family the FLO preflight recognises; expect it to block" ;;
  *)          BNK_DETECTED_CNI=unknown; warn "could not identify the CNI; FLO blocks when it cannot classify it" ;;
esac
export BNK_DETECTED_CNI

# FLO watches NetworkAttachmentDefinition from its first second and crash-loops without the Multus
# CRD, even on a host install that uses no attachments. Phase 10 installs it; say so now.
if kubectl get crd network-attachment-definitions.k8s.cni.cncf.io >/dev/null 2>&1; then
  ok "Multus CRD present"
else
  ok "Multus CRD absent: phase 10 installs it before FLO (FLO cannot start without it)"
fi

sc_count=$(kubectl get sc --no-headers 2>/dev/null | wc -l)
[[ "$sc_count" -gt 0 ]] || die "no StorageClass. BNK needs persistent volumes (e.g. local-path-provisioner)"
ok "StorageClass available: $(kubectl get sc --no-headers | awk '{print $1}' | paste -sd, -)"

# CPU. BNK requests ~22.5 vCPU in total (TMM alone 4.6). Below that, phase 50 does not fail, it sits
# Pending with "Insufficient cpu" until the timeout. Catch it here in two seconds.
need="${BNK_MIN_VCPU:-24}"
milli=$(kubectl get nodes -o jsonpath='{.items[*].status.allocatable.cpu}' | tr ' ' '\n' \
        | awk '/m$/{sub(/m$/,"");s+=$1;next} NF{s+=$1*1000} END{printf "%d",s}')
if [[ $(( ${milli:-0} / 1000 )) -lt "$need" ]]; then
  warn "~$(( ${milli:-0} / 1000 )) vCPU allocatable; BNK requests ~${need}. Expect Pending pods."
else
  ok "CPU: ~$(( milli / 1000 )) vCPU allocatable (BNK requests ~${need})"
fi

ok "profile host: TMM runs as a software pod, no DPU, no SR-IOV, MTU ${BNK_TMM_MTU:-1500}"
_IN_PREFLIGHT=0
