#!/usr/bin/env bash
# lab deliver <apps/...yaml>: deliver an app the way this cluster's owner does it, and say what happens.
# Safe to click on every path: it only applies the file itself on the Forge path, where nobody else will.
source "$(dirname "$0")/../lib.sh"; source "$(dirname "$0")/../ci-helpers.sh"
f="${1:-}"; [[ -n "$f" ]] || fail "usage: lab deliver apps/<app>/<file>.yaml (path inside the repository)"
o=$(gitea_api GET "/repos/${GITEA_ORG}/${GITEA_REPO}/actions/variables/BNK_INSTALLER" 2>/dev/null | jq -r '.data // .value // empty' || true)
on_main=no; file_on_main "$f" >/dev/null 2>&1 && on_main=yes
step "deliver $f  (owner: ${o:-none}, on main: $on_main)"
case "$o" in
  pipeline) [[ $on_main == yes ]] && ok "on main: the 'apps' workflow applies it (Gitea > Actions > apps)" \
                                  || echo "   merge the pull request first: the 'apps' workflow applies apps/ when it lands on main" ;;
  argocd)   [[ $on_main == yes ]] && ok "on main: Argo CD's 'apps' Application syncs it within about a minute (Argo CD tab)" \
                                  || echo "   merge the pull request first: Argo CD delivers only what is on main" ;;
  forge)    [[ $on_main == yes ]] || { echo "   merge the pull request first: deliver what was reviewed, from main"; exit 1; }
            file_on_main "$f" | kubectl apply -f - && ok "applied from main: on the Forge path, app teams deliver their own apps" ;;
  *)        fail "no install path chosen yet (challenge 5, 7 or 9)" ;;
esac
