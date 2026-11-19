# shellcheck shell=bash
# TMM's data-plane legs. In host mode TMM always has its pod interface; to own real network legs (an
# external VLAN toward the data-center router, an internal one toward the nodes) it gets extra
# interfaces from Multus. Each NetworkAttachmentDefinition is the recipe Multus follows when TMM's
# pod starts: "make a macvlan on the node's eth1 and hand it to the pod". TMM numbers them in order:
# the first listed in tmm.networks becomes 1.1, the second 1.2.
#
# They must exist before the CNEInstance names them, or the TMM pod cannot start.
if [[ -z "${BNK_NETWORK_ATTACHMENTS:-}" ]]; then
  ok "no tmm.networks declared: TMM runs with its pod interface only"; return 0
fi
if [[ "$DRY_RUN" == "1" ]] && ! kubectl get crd network-attachment-definitions.k8s.cni.cncf.io >/dev/null 2>&1; then
  ok "plan: would apply $(basename "$CLUSTER_ATTACHMENTS") (${BNK_NETWORK_ATTACHMENTS//,/, })"; return 0
fi
KA=(kubectl apply -n "$NS_BNK" -f "$CLUSTER_ATTACHMENTS"); [[ "$DRY_RUN" == "1" ]] && KA+=(--dry-run=server)
if [[ "$DRY_RUN" == "1" ]] && ! kubectl get ns "$NS_BNK" >/dev/null 2>&1; then
  ok "plan: would apply $(basename "$CLUSTER_ATTACHMENTS") into $NS_BNK (${BNK_NETWORK_ATTACHMENTS//,/, })"; return 0
fi
"${KA[@]}" >/dev/null
i=0
for a in ${BNK_NETWORK_ATTACHMENTS//,/ }; do
  i=$((i+1))
  if [[ "$DRY_RUN" == "1" ]] || kubectl get net-attach-def -n "$NS_BNK" "$a" >/dev/null 2>&1; then
    ok "TMM interface 1.${i} <- NetworkAttachmentDefinition ${a} ($(yq -r "select(.metadata.name == \"$a\") | .spec.config | from_json | .type + \" on \" + .master" "$CLUSTER_ATTACHMENTS" 2>/dev/null))"
  else
    die "tmm.networks names '$a' but $(basename "$CLUSTER_ATTACHMENTS") does not define it"
  fi
done
