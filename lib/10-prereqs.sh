# shellcheck shell=bash
# Cluster prerequisites: Multus (FLO needs its CRD), open-source cert-manager, and the CA issuer
# chain BNK's certificates are signed from. The guide's "Install and configure open source
# cert-manager" step. Order matters: Multus before FLO, and the CA chain is three objects.
KA=(kubectl apply -f -)
[[ "$DRY_RUN" == "1" ]] && KA=(kubectl apply --dry-run=server -f -)

# --- Multus -----------------------------------------------------------------------------------
if kubectl get crd network-attachment-definitions.k8s.cni.cncf.io >/dev/null 2>&1; then
  ok "Multus already present"
elif [[ "$DRY_RUN" == "1" ]]; then
  ok "plan: would install Multus ${MULTUS_VERSION}"
else
  kubectl apply -f "https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/${MULTUS_VERSION}/deployments/multus-daemonset.yml" >/dev/null
  ok "Multus ${MULTUS_VERSION} installed"
fi
if [[ "$DRY_RUN" == "0" ]] && kubectl -n kube-system get ds kube-multus-ds >/dev/null 2>&1; then
  kubectl -n kube-system set resources ds kube-multus-ds -c kube-multus --limits=memory="${MULTUS_MEMORY_LIMIT}" >/dev/null
  ok "Multus memory limit ${MULTUS_MEMORY_LIMIT} (the default OOMKills under BNK's CNI load)"
fi

# --- cert-manager -----------------------------------------------------------------------------
if kubectl get deploy -n cert-manager cert-manager-webhook >/dev/null 2>&1; then
  ok "cert-manager already present"
elif [[ "$DRY_RUN" == "1" ]]; then
  ok "plan: would install cert-manager ${CERT_MANAGER_VERSION}"
  ok "plan: would create ClusterIssuer ${CLUSTER_ISSUER} (CA ${CA_COMMON_NAME})"
  return 0   # nothing below can be validated server-side before cert-manager's CRDs exist
else
  kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml" >/dev/null
  kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=300s >/dev/null
  ok "cert-manager ${CERT_MANAGER_VERSION} installed"
fi

# "Rolled out" is not "serving": for a few seconds the API server's call to the webhook is still
# refused, which intermittently failed the very next apply. Probe until it accepts a request.
for _ in $(seq 1 60); do
  kubectl apply --dry-run=server -f - >/dev/null 2>&1 <<'PROBE' && break
apiVersion: cert-manager.io/v1
kind: Issuer
metadata: { name: webhook-readiness-probe, namespace: cert-manager }
spec: { selfSigned: {} }
PROBE
  sleep 3
done
ok "cert-manager webhook is serving"

# --- CA chain: self-signed issuer -> CA certificate -> CA ClusterIssuer -----------------------
# The CA CommonName MUST differ from the leaf CNs or CWC crash-loops on an x509 error.
"${KA[@]}" <<YAML >/dev/null
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: { name: temp-selfsigned }
spec: { selfSigned: {} }
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: f5-cne-ca, namespace: cert-manager }
spec:
  isCA: true
  commonName: ${CA_COMMON_NAME}
  secretName: f5-cne-ca-secret
  duration: 43800h
  privateKey: { algorithm: RSA, size: 4096, encoding: PKCS1 }
  issuerRef: { name: temp-selfsigned, kind: ClusterIssuer }
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: { name: ${CLUSTER_ISSUER} }
spec:
  ca: { secretName: f5-cne-ca-secret }
YAML
if [[ "$DRY_RUN" == "0" ]]; then
  kubectl wait --for=condition=Ready certificate/f5-cne-ca -n cert-manager --timeout=240s >/dev/null
  kubectl get secret f5-cne-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' \
    | base64 -d | openssl x509 -noout -text | grep -q 'CA:TRUE' || die "f5-cne-ca is not a CA certificate"
  ok "CA chain ready (CA:TRUE verified), ClusterIssuer ${CLUSTER_ISSUER}"
else
  ok "CA chain validates server-side"
fi
