#!/usr/bin/env bash
# lab forge-input <project> <input> <value>: change one input of the project's BNK module in Forge.
# Forge stores the Deploy form's values on the module (variable_overrides), and those win over the
# project's Variables tab. This is what the module's settings in the UI change. Then press Deploy all.
source "$(dirname "$0")/../lib.sh"
P="${1:-}"; K="${2:-}"; V="${3-}"
[[ -n "$P" && -n "$K" ]] || fail "usage: lab forge-input <project> <input> <value>   e.g. lab forge-input bnk-lab epp_namespaces inference"
pid=$(forge_api GET /api/projects | jq -r --arg n "$P" '(if type=="array" then . else (.items // .projects // []) end)[] | select(.name == $n) | .id' | head -1)
[[ -n "$pid" ]] || fail "no Forge project named '$P'"
m=$(forge_api GET "/api/project-modules/project/${pid}" | jq -c '(if type=="array" then . else (.items // .modules // []) end)[0]')
mid=$(jq -r '.id // empty' <<<"$m"); [[ -n "$mid" ]] || fail "project $P has no module"
step "module #$mid of project $P: $K"
echo "      before: $(jq -c --arg k "$K" '.variable_overrides[$k] // "(unset)"' <<<"$m")"
# Forge 4.3 answers the update with {success, message, warnings?}, not the module, so read it back.
r=$(forge_api PUT "/api/project-modules/${mid}" "$(jq -c --arg k "$K" --arg v "$V" '{variable_overrides: ((.variable_overrides // {}) + {($k): $v})}' <<<"$m")")
jq -r '.warnings // [] | .[] | "   warn  Forge: " + (if type=="string" then . else tojson end)' <<<"$r"
got=$(forge_api GET "/api/project-modules/project/${pid}" | jq -c --arg id "$mid" --arg k "$K" '(if type=="array" then . else (.items // .modules // []) end)[] | select((.id|tostring) == $id) | .variable_overrides[$k] // "(unset)"')
echo "      after:  $got"
[[ "$got" == "$(jq -c -n --arg v "$V" '$v')" ]] || fail "Forge did not keep $K=$V"
ok "now run: lab forge-apply $P   (Deploy all skips a module that is already applied)"
