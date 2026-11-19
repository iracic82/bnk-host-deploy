#!/usr/bin/env bash
# lab forge-secrets <project>: attach the three credentials the BNK module declares (secret_files in
# forge/bnk-host/bnkforge.artifact.json) to a Forge project, from the lab vault, never on screen.
#   kubeconfig               how the runner container reaches the cluster's API server
#   far_service_account_key  F5 Artifact Registry key
#   bnk_license_jwt          the licence
# They are FILE secrets, exactly what the UI's "Add File" button creates: Forge stores them encrypted
# and writes each one, mode 0600, to its path under /work/secrets in the runner at run time.
source "$(dirname "$0")/../lib.sh"
name="${1:-}"; [[ -n "$name" ]] || fail "usage: lab forge-secrets <project name>"
pid=$(forge_api GET /api/projects | jq -r --arg n "$name" '(if type=="array" then . else (.items // .projects // []) end)[] | select(.name == $n) | .id' | head -1)
[[ -n "$pid" ]] || fail "no Forge project named '$name' (Catalog > Deploy on the blueprint creates it)"
existing=$(forge_api GET "/api/projects/${pid}/secrets" | jq -c '(if type=="array" then . else (.secrets // .items // []) end)')

upload() {  # upload <secret name> <file name> <value-producing command...>
  local n=$1 fname=$2; shift 2
  local cur type id code T i
  cur=$(jq -c --arg n "$n" '[.[] | select(.name == $n)] | first // empty' <<<"$existing")
  type=$(jq -r '.secret_type // empty' <<<"${cur:-null}"); id=$(jq -r '.id // empty' <<<"${cur:-null}")
  local target; target=$(jq -r '.target_variable_name // empty' <<<"${cur:-null}")
  # Forge links a secret to the module's requirement by target_variable_name, not by its name.
  if [[ "$type" == file && "$target" == "$n" ]]; then ok "$n: file secret already on project $name, linked to the requirement"; return; fi
  if [[ -n "$id" ]]; then   # an earlier secret that is not a linked file secret: replace it
    forge_api DELETE "/api/projects/${pid}/secrets/${id}" >/dev/null && ok "$n: replacing the earlier secret with a linked file secret"
  fi
  T=$(mktemp -d); chmod 700 "$T"
  "$@" > "$T/$fname"
  for i in 1 2 3 4 5 6; do
    code=$(curl -sSk -o "$T/resp" -w '%{http_code}' -X POST -H "Authorization: Bearer ${_FORGE_TOKEN}" \
      -F "name=$n" -F "description=from lab-vault" -F "target_variable_name=$n" -F "target_module_path=forge/bnk-host" \
      -F "file=@$T/$fname;filename=$fname" \
      "https://127.0.0.1:8443/api/projects/${pid}/secrets/file") || code=000
    [[ "$code" == 429 ]] && { sleep $(( i * 5 )); continue; }; break
  done
  [[ "$code" =~ ^2 ]] || { echo "Forge answered $code: $(head -c 300 "$T/resp")" >&2; shred -u "$T/$fname" 2>/dev/null; rm -rf "$T"; fail "could not upload $n"; }
  shred -u "$T/$fname" 2>/dev/null; rm -rf "$T"
  ok "$n -> file secret on project $name (#$pid)"
}
step "file secrets for '$name'"
forge_api GET /api/auth/me >/dev/null
upload kubeconfig kubeconfig cat /root/.lab/kubeconfig-forge.yaml
upload far_service_account_key cne_pull_64.json vault_get far_service_account_key
upload bnk_license_jwt license.jwt vault_get bnk_license_jwt
step "what Forge now requires vs. holds"
forge_api GET "/api/projects/${pid}/secrets/required" | jq -r '
  ((.required_secrets // [])[] | "      \(.name)  \(if .exists then "present" else "MISSING" end)"),
  (if .all_satisfied then "   ok  all required secrets present: the module can run" else "   !!  \(.missing_count) required secret(s) missing" end)'
