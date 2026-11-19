# shellcheck shell=bash
# Registry auth, namespaces and the pull secret. The guide's "Create a pull-secret manifest for F5
# Artifact Registry" step. The same service-account key does three jobs: helm logs in to
# repo.f5.com with it (to pull the FLO and cert-gen charts), and the far-pull-secret it becomes lets
# the kubelets pull BNK's images. The secret must exist in BOTH namespaces.
#
# A plan logs in too: that proves the key is valid before anyone approves an install with it.
helm registry login --username _json_key_base64 --password-stdin "$CNE_REPO" < "$FAR_PULL_JSON" >/dev/null \
  || die "helm could not log in to ${CNE_REPO} with FAR_PULL_JSON. Is the key current?"
ok "the FAR key logs in to ${CNE_REPO}"

KA=(kubectl apply -f -)
[[ "$DRY_RUN" == "1" ]] && KA=(kubectl apply --dry-run=server -f -)
for ns in "$NS_CORE" "$NS_BNK"; do
  if [[ "$DRY_RUN" == "1" ]] && ! kubectl get ns "$ns" >/dev/null 2>&1; then
    ok "plan: would create namespace $ns and far-pull-secret in it"; continue
  fi
  kubectl create namespace "$ns" --dry-run=client -o yaml | "${KA[@]}" >/dev/null
  # The password is passed through a file, never on a command line where ps would show it.
  kubectl create secret docker-registry far-pull-secret \
    --docker-server="$CNE_REPO" --docker-username=_json_key_base64 \
    --docker-password="$(cat "$FAR_PULL_JSON")" \
    --namespace "$ns" --dry-run=client -o yaml | "${KA[@]}" >/dev/null
  ok "$ns: namespace and far-pull-secret$([[ $DRY_RUN == 1 ]] && echo ' (validated)')"
done
