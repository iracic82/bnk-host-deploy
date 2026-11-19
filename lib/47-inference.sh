# shellcheck shell=bash
# AI inference routing. BNK's controller can run F5 Endpoint Pickers (F5EPP): per-request schedulers
# that choose which model-server pod answers, by KV-cache prefix and load, through the Gateway API
# Inference Extension (an InferencePool behind an HTTPRoute). The controller only runs pickers in the
# namespaces the CNEInstance lists (eppNamespaces, set by phase 50 from inference.epp_namespaces).
#
# Order matters. Once eppNamespaces is set, the controller watches InferencePool from its first start
# and exits if the CRD is missing, and then TMM is no longer configured. So the CRDs, and every picker
# namespace with its F5 pull secret, are put in place here, before phase 50 touches the CNEInstance.
if [[ -z "${BNK_EPP_NAMESPACES:-}" ]]; then
  ok "no inference.epp_namespaces: endpoint pickers not enabled"; return 0
fi
GAIE_URL="https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/${GAIE_VERSION}/manifests.yaml"
CRD=inferencepools.inference.networking.k8s.io

if [[ "$DRY_RUN" == "1" ]]; then
  if kubectl get crd "$CRD" >/dev/null 2>&1; then ok "Inference Extension CRDs already present"
  else ok "plan: would install the Gateway API Inference Extension CRDs ${GAIE_VERSION} (InferencePool)"; fi
else
  kubectl apply --server-side --force-conflicts -f "$GAIE_URL" >/dev/null \
    || die "could not apply the Inference Extension CRDs from $GAIE_URL"
  kubectl wait --for=condition=Established "crd/$CRD" --timeout=120s >/dev/null \
    || die "CRD $CRD did not become Established"
  ok "Inference Extension CRDs ${GAIE_VERSION} installed (InferencePool), before the controller is told to watch them"
fi

for ns in ${BNK_EPP_NAMESPACES//,/ }; do
  if kubectl get ns "$ns" >/dev/null 2>&1 && kubectl -n "$ns" get secret far-pull-secret >/dev/null 2>&1; then
    ok "endpoint-picker namespace $ns: present, with far-pull-secret"; continue
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    ok "plan: would prepare endpoint-picker namespace $ns (namespace + far-pull-secret)"; continue
  fi
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl label namespace "$ns" bnk-host-deploy.io/epp=true --overwrite >/dev/null
  # the controller renders the picker's Deployment here, and its image comes from F5's registry
  kubectl -n "$NS_BNK" get secret far-pull-secret -o json \
    | jq 'del(.metadata.namespace, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp,
              .metadata.ownerReferences, .metadata.managedFields, .metadata.annotations)' \
    | kubectl -n "$ns" apply -f - >/dev/null \
    || die "could not copy far-pull-secret into $ns (phase 20 creates it in $NS_BNK)"
  ok "endpoint-picker namespace $ns prepared (namespace + far-pull-secret)"
done
