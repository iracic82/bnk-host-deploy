#!/usr/bin/env bash
# lab owner: which tool owns installing BNK on this cluster, and how a merged change to apps/ reaches it.
source "$(dirname "$0")/../lib.sh"
o=$(gitea_api GET "/repos/${GITEA_ORG}/${GITEA_REPO}/actions/variables/BNK_INSTALLER" 2>/dev/null | jq -r '.data // .value // empty')
case "$o" in
  pipeline) how="the 'apps' workflow applies apps/ when your merge lands on main (Gitea > Actions)" ;;
  argocd)   how="Argo CD's 'apps' Application syncs apps/ by itself, within about a minute of the merge (Argo CD tab)" ;;
  forge)    how="Forge installs the platform, not apps. After the merge, apply apps/ yourself: kubectl apply -f apps/hello/hello.yaml" ;;
  *)        how="nobody yet: choose an install path first (challenges 5, 7 or 9)" ;;
esac
step "BNK owner on this cluster: ${o:-none}"
echo "   delivery of apps/: $how"
