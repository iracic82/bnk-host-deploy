# shellcheck shell=bash
# Wait for the data plane. With the licence Active, f5-cne-controller creates and configures TMM and
# the CNEInstance turns Available. Unlicensed, the controller logs "License is not enabled.. skip
# Resource controllers" and never creates TMM, so then we wait for everything a licence does not gate.
[[ "$DRY_RUN" == "1" ]] && { ok "plan: would wait up to ${BNK_WAIT_TIMEOUT}s for CNEInstance Available"; return 0; }

deadline=$(( $(date +%s) + BNK_WAIT_TIMEOUT ))
avail=""; pending=""
while [[ $(date +%s) -lt $deadline ]]; do
  conds=$(kubectl get cneinstance f5-bnk-instance -n "$NS_BNK" \
            -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}' 2>/dev/null || true)
  avail=$(tr ' ' '\n' <<<"$conds" | sed -n 's/^Available=//p' | head -1)
  [[ "$avail" == "True" ]] && break
  pending=$(tr ' ' '\n' <<<"$conds" | grep '=False$' | sed 's/=False//' | paste -sd, - || true)
  if [[ "$SKIP_LICENSE" == "1" ]]; then
    pending=$(tr ',' '\n' <<<"$pending" | grep -vE '^(Available|F5TmmAvailable)$' | paste -sd, - || true)
    [[ -z "$pending" && "$conds" == *"Reconciled=True"* ]] && break
  fi
  printf '\r    waiting, not ready yet: %-52s' "${pending:-starting}"
  sleep 15
done
printf '\r%-80s\r' ' '

if [[ "$avail" == "True" ]]; then
  ok "CNEInstance Available: TMM is up on $(kubectl get pods -n "$NS_BNK" -l app=f5-tmm -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || echo '?')"
  # An internal VLAN on the node network: a node ARPs for TMM's pod address from its node address, and
  # BIG-IP's default arp.verifyreturnroute drops that request because the return route leaves on the
  # internal VLAN. When the node's ARP entry ages out the controller loses its channel to TMM. No
  # CNEInstance field carries TMM db keys; the tmm-init ConfigMap does, and TMM re-reads it each second.
  if [[ -n "${CLUSTER_NETWORK:-}" ]] && grep -q 'internal: true' "$CLUSTER_NETWORK"; then
    cur=$(kubectl -n "$NS_BNK" get cm tmm-init -o jsonpath='{.data.user_conf\.tcl}' 2>/dev/null || true)
    if [[ -z "$cur" ]]; then warn "no tmm-init ConfigMap yet; arp.verifyreturnroute not set"
    elif grep -q 'arp.verifyreturnroute disable' <<<"$cur"; then ok "TMM db key arp.verifyreturnroute=disable present"
    else
      jq -n --arg c "$cur" '{data:{"user_conf.tcl": ("\n\t\tbigdb arp.verifyreturnroute disable\n" + $c)}}' \
        | kubectl -n "$NS_BNK" patch cm tmm-init --type merge --patch-file /dev/stdin >/dev/null
      ok "TMM db key arp.verifyreturnroute=disable set (internal VLAN shares the node network)"
    fi
  fi
elif [[ "$SKIP_LICENSE" == "1" && -z "$pending" ]]; then
  ok "control plane ready. Available stays False without a licence, which is expected"
else
  # Say whether this is slow or broken: the two need opposite responses.
  echo "    still not ready after ${BNK_WAIT_TIMEOUT}s: ${pending:-unknown}"
  kubectl get sts,deploy -n "$NS_BNK" -o 'custom-columns=KIND:.kind,NAME:.metadata.name,WANT:.spec.replicas,READY:.status.readyReplicas' --no-headers 2>/dev/null \
    | awk '{r=($4=="<none>"?0:$4); if (r!=$3) printf "      %s/%s %s/%s ready\n",$1,$2,r,$3}' || true
  stuck=$(kubectl get pods -A -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.state.waiting.reason}{"\n"}{end}{end}' \
            | grep -c 'ImagePullBackOff\|ErrImagePull\|CrashLoopBackOff' || true)
  kubectl logs -n "$NS_CORE" deploy/f5-lifecycle-operator --tail=300 2>/dev/null \
    | grep -iE '"l"="error"|panic|CNEInstance' | tail -8 | cut -c1-220 | sed 's/^/      /' || true
  if [[ "${stuck:-0}" -gt 0 ]]; then die "$stuck container(s) failing to pull or crash-looping: a real failure, not slowness"; fi
  die "timed out; nothing is failing, so the stack is still coming up. Re-run this phase: ./install.sh --cluster <file> --phase 65"
fi
