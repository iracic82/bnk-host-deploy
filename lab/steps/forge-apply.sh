#!/usr/bin/env bash
# lab forge-apply [project]: re-run the project's BNK module, the way its row's own Deploy does.
# Why not Deploy all: Forge 4.3 skips a module that is already applied unless it sees its inputs
# change, and it only tracks that for modules it planned itself. A container module like ours is
# always "unchanged", so after a new input Deploy all does nothing. The per-module deploy has no
# such skip. The installer converges: everything that already matches is a quick "ok".
source "$(dirname "$0")/../lib.sh"
P="${1:-bnk-lab}"
pid=$(forge_api GET /api/projects | jq -r --arg n "$P" '(if type=="array" then . else (.items // .projects // []) end)[] | select(.name == $n) | .id' | head -1)
[[ -n "$pid" ]] || fail "no Forge project named '$P'"
mods() { forge_api GET "/api/project-modules/project/${pid}" | jq -c '(if type=="array" then . else (.items // .modules // []) end)[0]'; }
m=$(mods); mid=$(jq -r '.id // empty' <<<"$m"); [[ -n "$mid" ]] || fail "project $P has no module"
step "re-run module #$mid of $P (inputs: $(jq -c '.variable_overrides // {}' <<<"$m"))"
forge_api POST "/api/project-modules/${mid}/deploy" '{}' >/dev/null
ok "started: follow it in Forge > Build > Workspaces > ${P}"
seen=""
for _ in $(seq 1 240); do
  s=$(mods | jq -r '.status // .state // "?"')
  [[ "$s" != "$seen" ]] && { echo "   module status: $s"; seen="$s"; }
  case "$s" in applied|deployed|success|completed) [[ -n "${started:-}" ]] && { ok "applied"; exit 0; } ;; failed|error) fail "the deploy failed: open the module's logs in Forge" ;; *) started=1 ;; esac
  sleep 10
done
warn "still running after 40 minutes, keep watching in Forge"
