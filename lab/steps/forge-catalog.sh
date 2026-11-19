#!/usr/bin/env bash
# lab forge-catalog: what you do in Forge's UI to load the installer, done through the same API the
# UI calls. Use it if you want to skip the clicks, or read it to see what each click does.
#   1. Module Sources: add this repository; sync. Forge finds forge/bnk-host/bnkforge.pack.json,
#      validates it (digest-pinned image, argv-only steps, non-root) and lists the module.
#   2. Blueprint Sources: add the same repository; sync. Forge finds forge/forge-blueprint.json and
#      creates a release "discovered".
#   3. Import the release: it becomes deployable.
source "$(dirname "$0")/../lib.sh"
URL="http://$(vm_ip):${PORT_GITEA}/${GITEA_ORG}/${GITEA_REPO}.git"

step "1/3  module source -> ${URL}"
mid=$(forge_api GET /api/module-sources | jq -r --arg u "$URL" '(if type=="array" then . else (.items // .sources // .projects // .clusters // .modules // .secrets // []) end)[] | select(.url == $u) | .id' | head -1)
[[ -n "$mid" ]] || mid=$(forge_api POST /api/module-sources "{\"name\":\"bnk-host-deploy\",\"source_type\":\"git\",\"url\":\"${URL}\",\"branch\":\"main\"}" | jq -r .id)
forge_api POST "/api/module-sources/${mid}/sync" | jq -r '"   sync: " + ((.status // .sync_status // "done")|tostring) + "  " + ((.modules_added // .added // "") | tostring)' || true
forge_api GET "/api/module-sources/${mid}/modules" | jq -r '(if type=="array" then . else (.items // .sources // .projects // .clusters // .modules // .secrets // []) end)[] | "   module: \(.source_path // .path)  v\(.source_version // .version)  (\(.name))"' || true

step "2/3  blueprint source -> ${URL}"
bid=$(forge_api GET /api/blueprint-catalog/sources | jq -r --arg u "$URL" '.[]? | select(.url == $u) | .id' | head -1)
[[ -n "$bid" ]] || bid=$(forge_api POST /api/blueprint-catalog/sources "{\"name\":\"bnk-host-deploy\",\"source_type\":\"git\",\"url\":\"${URL}\",\"branch\":\"main\"}" | jq -r .id)
forge_api POST "/api/blueprint-catalog/sources/${bid}/sync" >/dev/null
rel=$(forge_api GET /api/blueprint-catalog/releases | jq -c '[.[]? | select(.blueprint_id == "bnk-host-2-4")] | sort_by(.id) | last')
[[ "$rel" != null && -n "$rel" ]] || fail "the blueprint bnk-host-2-4 was not discovered; check the source's sync status in Forge"
ok "release $(jq -r '"#\(.id) \(.blueprint_id) v\(.blueprint_version) state=\(.release_state)"' <<<"$rel")"

step "3/3  import it (make it deployable)"
rid=$(jq -r .id <<<"$rel")
[[ "$(jq -r .release_state <<<"$rel")" == imported ]] || forge_api POST "/api/blueprint-catalog/releases/${rid}/import" >/dev/null
ok "BNK 2.4.2 Host on an existing cluster: imported (Build > Catalog)"
