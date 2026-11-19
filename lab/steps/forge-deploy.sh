#!/usr/bin/env bash
# lab forge-deploy [project] [tmm-node]: create the project from the imported blueprint (if it does
# not exist), attach the credentials, and press Deploy, through Forge's API. Then follow the steps.
source "$(dirname "$0")/../lib.sh"
P="${1:-bnk-lab}"; NODE="${2:-bnk-worker}"
rid=$(forge_api GET /api/blueprint-catalog/releases | jq -r '[.[]? | select(.blueprint_id == "bnk-host-2-4" and .release_state == "imported")] | sort_by(.id) | last | .id // empty')
[[ -n "$rid" ]] || fail "no imported bnk-host-2-4 release: run 'lab forge-catalog' (or import it in Build > Catalog)"
pid=$(forge_api GET /api/projects | jq -r --arg n "$P" '(.projects // .items // .)[]? | select(.name == $n) | .id' | head -1)
if [[ -z "$pid" ]]; then
  pid=$(forge_api POST "/api/stacks/releases/${rid}/projects" \
    "{\"name\":\"${P}\",\"description\":\"BNK 2.4.2 on the lab cluster\",\"environment\":\"lab\",\"variables\":{\"tmm_node\":\"${NODE}\",\"cluster_name\":\"lab\"}}" | jq -r .project_id)
  ok "project ${P} (#${pid}) created from release #${rid}, tmm_node=${NODE}"
else
  ok "project ${P} (#${pid}) exists"
fi
bash "$(dirname "$0")/forge-secrets.sh" "$P"
step "deploy"
h=$(forge_api POST "/api/projects/${pid}/deploy-all" '{}' | jq -r '.run_handle // .handle // .id // empty')
ok "deploy started${h:+ (run $h)}: follow it in Forge > Projects > ${P}"
for _ in $(seq 1 240); do
  m=$(forge_api GET "/api/project-modules/project/${pid}" | jq -c '[(.modules // .items // .)[]? | {s: (.status // .state)}] | first')
  s=$(jq -r '.s // "?"' <<<"$m")
  printf '\r   module status: %-20s' "$s"
  case "$s" in applied|deployed|success|completed) echo; ok "applied"; exit 0 ;; failed|error) echo; fail "the deploy failed: open the module's logs in Forge" ;; esac
  sleep 15
done
echo; warn "still running after an hour; keep watching in Forge"
