# shellcheck shell=bash
# CNEInstance. The whole data plane shape lives in this one object: FLO reads it and installs every
# BNK component from the release manifest. The guide's "Install a CNE instance using FLO" step.
#
# This phase applies the object and waits only until the operator has laid the stack out and
# registered BNK's own CRDs (the License CRD among them). It deliberately does NOT wait for
# Available: on a licensed install the controller configures TMM only after the licence is Active,
# so waiting for Available here, before phase 60, can only time out. Phase 65 does that wait.
# shellcheck source=lib/render.sh
source "$HERE/lib/render.sh"

sc="${BNK_STORAGECLASS:-}"
if [[ -z "$sc" ]] || ! kubectl get sc "$sc" >/dev/null 2>&1; then
  sc="$(kubectl get sc -o jsonpath='{.items[0].metadata.name}')"
fi
_render_sc="$sc"
rendered="$(render_cneinstance "$HERE/profiles/host.yaml")"

if [[ "$DRY_RUN" == "1" ]]; then
  if kubectl get crd cneinstances.k8s.f5.com >/dev/null 2>&1; then
    echo "$rendered" | kubectl apply -n "$NS_BNK" --dry-run=server -f - >/dev/null \
      && ok "CNEInstance validates server-side against the installed CRD" \
      || die "the API server rejected the rendered CNEInstance"
  fi
  if kubectl -n "$NS_BNK" get cneinstance f5-bnk-instance >/dev/null 2>&1; then
    # kubectl diff: what this commit would change on the live object (exit 1 means "differs")
    d=$(echo "$rendered" | kubectl diff -n "$NS_BNK" -f - 2>/dev/null | grep -vE '^(diff |--- |\+\+\+ )' | grep -vE '^[ +-] +(generation|resourceVersion|uid|creationTimestamp|managedFields):' || true)
    if [[ -n "$d" ]]; then
      echo "$d" | sed 's/^/    /'
      report_diff "CNEInstance f5-bnk-instance would change (diff against the live object)" "$d"
    else
      ok "CNEInstance f5-bnk-instance: live object already matches"
    fi
  else
    ok "plan: would create CNEInstance f5-bnk-instance (release manifest ${CNE_RELEASE_MANIFEST}, size ${BNK_DEPLOYMENT_SIZE})"
  fi
  echo "    ---- rendered CNEInstance ----"; echo "$rendered" | sed 's/^/    /'
  { echo; echo '<details><summary>Rendered CNEInstance</summary>'; echo; echo '```yaml'; echo "$rendered"; echo '```'; echo '</details>'; } >> "$_SUMMARY"
  return 0
fi

echo "$rendered" | kubectl apply -n "$NS_BNK" -f - >/dev/null
ok "CNEInstance f5-bnk-instance applied: manifest ${CNE_RELEASE_MANIFEST}, size ${BNK_DEPLOYMENT_SIZE}, storage ${sc}"
echo "    FLO is now pulling ~80 components from the release manifest; this takes several minutes"

deadline=$(( $(date +%s) + BNK_WAIT_TIMEOUT ))
while [[ $(date +%s) -lt $deadline ]]; do
  reconciled=$(kubectl get cneinstance f5-bnk-instance -n "$NS_BNK" \
                 -o jsonpath='{.status.conditions[?(@.type=="Reconciled")].status}' 2>/dev/null || true)
  if kubectl get crd licenses.k8s.f5net.com >/dev/null 2>&1 && [[ "$reconciled" == "True" ]]; then break; fi
  running=$(kubectl get pods -n "$NS_BNK" --no-headers 2>/dev/null | grep -c Running || true)
  printf '\r    reconciling: Reconciled=%-6s %3s pods running in %s ' "${reconciled:-?}" "$running" "$NS_BNK"
  sleep 15
done
printf '\r%-78s\r' ' '
kubectl get crd licenses.k8s.f5net.com >/dev/null 2>&1 \
  || die "the License CRD never appeared within ${BNK_WAIT_TIMEOUT}s. kubectl logs -n $NS_CORE deploy/f5-lifecycle-operator"
ok "operator reconciled the CNEInstance and registered BNK's CRDs ($(kubectl get crd -o name | grep -c 'k8s.f5') F5 CRDs)"
