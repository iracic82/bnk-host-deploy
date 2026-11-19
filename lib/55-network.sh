# shellcheck shell=bash
# TMM's network: VLANs with self IPs on the legs from phase 45, the VIP pool Gateways draw addresses
# from, and the GatewayClass that binds Gateway API objects to this BNK instance. These are F5 custom
# resources, so they can only be applied once the CNEInstance has registered BNK's CRDs (phase 50),
# and every one of them passes F5's validation webhook.
#
# Applying them before the licence is deliberate: when TMM starts it finds its network waiting.
if [[ -z "${CLUSTER_NETWORK:-}" ]]; then ok "no ${CLUSTER_NAME:-cluster}.network.yaml: nothing to apply"; return 0; fi
if [[ "$DRY_RUN" == "1" ]]; then
  if kubectl get crd f5-spk-vlans.k8s.f5net.com >/dev/null 2>&1; then
    kubectl apply --dry-run=server -f "$CLUSTER_NETWORK" >/dev/null && ok "$(basename "$CLUSTER_NETWORK") validates server-side, F5 webhook included" \
      || die "the API server or F5's webhook rejected $(basename "$CLUSTER_NETWORK")"
    d=$(kubectl diff -f "$CLUSTER_NETWORK" 2>/dev/null | grep -vE '^(diff |--- |\+\+\+ )' | grep -vE '^[ +-] +(generation|resourceVersion|uid|creationTimestamp):' || true)
    if [[ -n "$d" ]]; then report_diff "TMM network ($(basename "$CLUSTER_NETWORK")) would change" "$d"; echo "$d" | sed 's/^/    /'
    else ok "TMM network: live objects already match $(basename "$CLUSTER_NETWORK")"; fi
  else
    ok "plan: would apply $(basename "$CLUSTER_NETWORK"): $(yq -N -r '.kind + "/" + .metadata.name' "$CLUSTER_NETWORK" | paste -sd' ' -)"
  fi
  return 0
fi

# The webhook pod restarts with the stack; until it listens, every F5 object is refused with
# "failed calling webhook". Wait for an endpoint, then retry only that error.
for _ in $(seq 1 60); do
  [[ -n "$(kubectl -n "$NS_BNK" get endpoints f5-validation-svc -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)" ]] && break
  sleep 5
done
out=""
for attempt in $(seq 1 12); do
  if out=$(kubectl apply -f "$CLUSTER_NETWORK" 2>&1); then break; fi
  grep -qE 'failed calling webhook|connection refused|no endpoints available' <<<"$out" || die "applying $(basename "$CLUSTER_NETWORK") failed: $out"
  wait_note "F5 webhook still starting (${attempt}/12), retrying"; sleep 10
done
grep -qE 'failed calling webhook' <<<"$out" && die "the F5 webhook kept refusing $(basename "$CLUSTER_NETWORK")"
while read -r line; do [[ -n "$line" ]] && ok "$line"; done <<<"$out"
