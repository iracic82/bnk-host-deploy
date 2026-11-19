#!/usr/bin/env bash
# lab ci-secrets: give the pipeline its two credentials, from the lab vault into the repository's
# Actions secrets, without either value appearing on screen, in a file or in git.
#
#   FAR_PULL_B64     the F5 Artifact Registry service-account key: pulls FLO, cert-gen and every BNK image
#   BNK_LICENSE_JWT  the licence token BNK validates with F5 in connected mode
#
# Workflows read them as ${{ secrets.NAME }}; the runner masks them in logs. On GitHub you would add
# them under Settings > Secrets and variables > Actions, ideally on an environment with reviewers.
source "$(dirname "$0")/../lib.sh"
REPO="${GITEA_ORG}/${GITEA_REPO}"
put() {  # put <SECRET_NAME> <vault key>
  vault_get "$2" | jq -Rs '{data: .}' \
    | curl -fsS -X PUT -u "${LAB_USER}:$(lab_secret gitea-password)" -H 'Content-Type: application/json' \
        --data @- "http://127.0.0.1:${PORT_GITEA}/api/v1/repos/${REPO}/actions/secrets/$1" -o /dev/null
  ok "$1 <- vault:$2"
}
step "copying from lab-vault/bnk-credentials into ${REPO}'s Actions secrets"
put FAR_PULL_B64 far_service_account_key
put BNK_LICENSE_JWT bnk_license_jwt
step "what the repository now holds (names only, values are write-only)"
gitea_api GET "/repos/${REPO}/actions/secrets" | jq -r '.[] | "      \(.name)   created \(.created_at[0:19])"'

set_owner pipeline
