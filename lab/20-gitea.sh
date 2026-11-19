#!/usr/bin/env bash
# The lab's "GitHub": Gitea with Gitea Actions, which runs the repository's .github/workflows as they
# are. Setup gives it a learner account, the platform/bnk-host-deploy repository and branch
# protection on main. It does NOT register a CI runner or add secrets: the learner does both.
source "$(dirname "$0")/lib.sh"
IP=$(vm_ip)
PW=$(lab_secret gitea-password)

step "Gitea ${GITEA_IMAGE}"
if ! docker ps --format '{{.Names}}' | grep -qx gitea; then
  docker rm -f gitea >/dev/null 2>&1 || true
  # The Instruqt tab adds "X-WEBAUTH-USER: learner" to every request (reverse-proxy authentication),
  # so the learner is signed in without a password; git and the API still use the password.
  # ROOT_URL is the address the runner and Forge clone from; PUBLIC_URL_DETECTION=auto makes the
  # web UI build its links from the browser's host instead (the Instruqt tab URL).
  docker run -d --name gitea --restart unless-stopped -p "${PORT_GITEA}:3000" -v /var/lib/gitea:/data \
    -e USER_UID=1000 -e USER_GID=1000 \
    -e GITEA__database__DB_TYPE=sqlite3 \
    -e GITEA__security__INSTALL_LOCK=true \
    -e GITEA__server__ROOT_URL="http://${IP}:${PORT_GITEA}/" \
    -e GITEA__server__PUBLIC_URL_DETECTION=auto \
    -e GITEA__server__DISABLE_SSH=true \
    -e GITEA__service__DISABLE_REGISTRATION=true \
    -e GITEA__actions__ENABLED=true \
    -e GITEA__actions__DEFAULT_ACTIONS_URL=github \
    -e GITEA__repository__DEFAULT_BRANCH=main \
    -e GITEA__security__CSRF_COOKIE_HTTP_ONLY=true \
    -e GITEA__cors__ENABLED=false \
    -e GITEA__webhook__ALLOWED_HOST_LIST='*' \
    -e GITEA__service__ENABLE_REVERSE_PROXY_AUTHENTICATION=true \
    -e GITEA__security__REVERSE_PROXY_AUTHENTICATION_USER=X-WEBAUTH-USER \
    -e GITEA__security__REVERSE_PROXY_TRUSTED_PROXIES='*' \
    "$GITEA_IMAGE" >/dev/null
fi
for _ in $(seq 1 90); do curl -fsS "http://127.0.0.1:${PORT_GITEA}/api/healthz" >/dev/null 2>&1 && break; sleep 2; done
curl -fsS "http://127.0.0.1:${PORT_GITEA}/api/healthz" >/dev/null || fail "Gitea did not come up"
ok "Gitea on :${PORT_GITEA}, version $(curl -fsS "http://127.0.0.1:${PORT_GITEA}/api/v1/version" | jq -r .version)"

step "learner account and the platform organisation"
if ! docker exec -u git gitea gitea admin user list 2>/dev/null | awk '{print $2}' | grep -qx "$LAB_USER"; then
  docker exec -u git gitea gitea admin user create --admin --username "$LAB_USER" --password "$PW" \
    --email "${LAB_USER}@lab.local" --must-change-password=false >/dev/null
fi
gitea_api GET "/orgs/${GITEA_ORG}" >/dev/null 2>&1 || gitea_api POST /orgs "{\"username\":\"${GITEA_ORG}\",\"full_name\":\"Platform Team\",\"visibility\":\"public\"}" >/dev/null
ok "user ${LAB_USER}, org ${GITEA_ORG}"

step "repository ${GITEA_ORG}/${GITEA_REPO}"
if ! gitea_api GET "/repos/${GITEA_ORG}/${GITEA_REPO}" >/dev/null 2>&1; then
  gitea_api POST "/orgs/${GITEA_ORG}/repos" "{\"name\":\"${GITEA_REPO}\",\"private\":false,\"default_branch\":\"main\",\"description\":\"Install F5 BIG-IP Next for Kubernetes (Host) from git\"}" >/dev/null
  # Publish everything but the lab harness itself: the learner works with the product repository.
  T=$(mktemp -d); git -C "$LAB_REPO_DIR" archive HEAD | tar -x -C "$T"; rm -rf "$T/lab" "$T/instruqt"
  git -C "$T" init -q -b main
  git -C "$T" -c user.name="Platform Team" -c user.email=platform@lab.local add -A
  git -C "$T" -c user.name="Platform Team" -c user.email=platform@lab.local commit -qm "bnk-host-deploy: BNK ${BNK_VERSION:-2.4.2} host installer, CI, Forge module, Argo CD apps"
  git -C "$T" push -q "http://${LAB_USER}:${PW}@127.0.0.1:${PORT_GITEA}/${GITEA_ORG}/${GITEA_REPO}.git" main
  rm -rf "$T"
fi
gitea_api PATCH "/repos/${GITEA_ORG}/${GITEA_REPO}" '{"has_actions":true,"allow_merge_commits":true,"allow_squash_merge":true,"default_merge_style":"merge"}' >/dev/null
ok "http://${IP}:${PORT_GITEA}/${GITEA_ORG}/${GITEA_REPO}"

step "branch protection: main changes only through pull requests"
gitea_api GET "/repos/${GITEA_ORG}/${GITEA_REPO}/branch_protections/main" >/dev/null 2>&1 || \
  gitea_api POST "/repos/${GITEA_ORG}/${GITEA_REPO}/branch_protections" \
    '{"branch_name":"main","rule_name":"main","enable_push":false,"enable_status_check":false,"required_approvals":0,"block_on_outdated_branch":false}' >/dev/null
ok "direct pushes to main are refused"

step "the learner's working copy"
mkdir -p "$(dirname "$WORKSPACE")"
if [[ ! -d "$WORKSPACE/.git" ]]; then
  git clone -q "http://127.0.0.1:${PORT_GITEA}/${GITEA_ORG}/${GITEA_REPO}.git" "$WORKSPACE"
fi
git config --global user.name "Lab Learner"; git config --global user.email "${LAB_USER}@lab.local"
git config --global credential.helper store; git config --global init.defaultBranch main
printf 'http://%s:%s@127.0.0.1:%s\n' "$LAB_USER" "$PW" "$PORT_GITEA" > /root/.git-credentials; chmod 600 /root/.git-credentials
ok "$WORKSPACE (origin = Gitea, credentials stored)"
