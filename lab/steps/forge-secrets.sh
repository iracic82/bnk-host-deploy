#!/usr/bin/env bash
# lab forge-secrets <project>: attach the three credentials the BNK module declares (secret_files in
# forge/bnk-host/bnkforge.artifact.json) to a Forge project, from the lab vault, never on screen.
#   kubeconfig               how the runner container reaches the cluster's API server
#   far_service_account_key  F5 Artifact Registry key
#   bnk_license_jwt          the licence
# Forge stores them encrypted and writes them, mode 0600, into the runner's /work/secrets at run time.
source "$(dirname "$0")/../lib.sh"
name="${1:-}"; [[ -n "$name" ]] || fail "usage: lab forge-secrets <project name>"
pid=$(forge_api GET /api/projects | jq -r --arg n "$name" '(.projects // .items // .)[]? | select(.name == $n) | .id' | head -1)
[[ -n "$pid" ]] || fail "no Forge project named '$name' (Projects page: create it first)"
have=$(forge_api GET "/api/projects/${pid}/secrets" | jq -r '(.secrets // .items // .)[]?.name' 2>/dev/null || true)
put() {  # put <name> <value-producing command...>
  local n=$1; shift
  if grep -qx "$n" <<<"$have"; then ok "$n already set on project $name"; return; fi
  "$@" | jq -Rs --arg n "$n" '{name: $n, value: ., description: "from lab-vault"}' \
    | curl -fsSk -X POST -H "Authorization: Bearer ${_FORGE_TOKEN}" -H 'Content-Type: application/json' \
        --data @- "https://127.0.0.1/api/projects/${pid}/secrets/value" -o /dev/null
  ok "$n -> project $name (#$pid)"
}
step "project secrets for '$name'"
forge_api GET /api/auth/me >/dev/null
put kubeconfig cat /root/.lab/kubeconfig-forge.yaml
put far_service_account_key vault_get far_service_account_key
put bnk_license_jwt vault_get bnk_license_jwt
