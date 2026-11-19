# shellcheck shell=bash
# Label the TMM node. The guide's "Label TMM nodes" step: "If no nodes are labeled, the
# container-orchestration platform won't schedule any TMM pods." Skip it and the operator panics
# with "assignment to entry in nil map" at f5tmm_daemonset.go, a message that names neither TMM nor
# the label. So the cluster file declares the node, and this phase applies and proves the label.
TMM_LABEL="app=f5-tmm"
declared="${BNK_TMM_NODES:-}"

for n in ${declared//,/ }; do
  kubectl get node "$n" >/dev/null 2>&1 || die "the cluster file names TMM node '$n', which is not in this cluster (kubectl get nodes)"
done
[[ -n "$declared" ]] && ok "cluster file declares the TMM node: ${declared//,/ }"

if [[ "${BNK_TMM_MANAGE_LABELS:-false}" == "true" && -n "$declared" ]]; then
  if [[ "$DRY_RUN" == "1" ]]; then
    for n in ${declared//,/ }; do
      if [[ "$(kubectl get node "$n" -o jsonpath='{.metadata.labels.app}' 2>/dev/null)" == f5-tmm ]]; then
        ok "$n already carries $TMM_LABEL"
      else
        ok "plan: would label $n with $TMM_LABEL"
      fi
    done
  else
    for n in ${declared//,/ }; do
      kubectl label node "$n" "$TMM_LABEL" --overwrite >/dev/null
      ok "labelled $n $TMM_LABEL"
    done
  fi
fi
[[ "$DRY_RUN" == "1" ]] && return 0

labelled=$(kubectl get nodes -l "$TMM_LABEL" --no-headers 2>/dev/null | wc -l)
if [[ "${labelled:-0}" -eq 0 ]]; then
  die "no node carries $TMM_LABEL, so TMM would never schedule. Declare tmm.nodes in the cluster file (with manage_labels: true), or: kubectl label node <NODE> $TMM_LABEL"
fi
if [[ "$labelled" -gt 1 && "${BNK_TMM_ALLOW_MULTI:-false}" != "true" ]]; then
  die "$labelled nodes carry $TMM_LABEL. This repository is qualified with one TMM node; remove the extra labels or set BNK_TMM_ALLOW_MULTI=true"
fi
ok "$labelled node carries $TMM_LABEL"

# TMM requests hugepages-2Mi in every profile and the operator keeps that request whatever you
# override. A labelled node without them gives a Pending pod and no message mentioning hugepages.
for n in $(kubectl get nodes -l "$TMM_LABEL" -o name | cut -d/ -f2); do
  hp=$(kubectl get node "$n" -o jsonpath='{.status.allocatable.hugepages-2Mi}' 2>/dev/null)
  case "${hp:-0}" in
    0|"") die "node $n is labelled for TMM but advertises no hugepages-2Mi. Reserve them on the node (sysctl vm.nr_hugepages=2048) and restart its kubelet" ;;
    *)    ok "node $n advertises ${hp} of 2Mi hugepages for TMM" ;;
  esac
done
