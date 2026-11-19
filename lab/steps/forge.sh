#!/usr/bin/env bash
# lab forge: install BNK Forge 4.0.0, F5's deployment and lifecycle tool for BNK, the way its README
# says: the release's dist bundle, an .env, and ./install.sh. Forge runs as Docker containers on this
# VM: an API, Celery workers that run deployment steps, a React UI, Postgres, Redis and a scoped
# Docker socket proxy through which it launches the runner containers its modules ask for.
source "$(dirname "$0")/../lib.sh"
SRC=/opt/bnk-forge-src; DST=/opt/bnk-forge

step "1/6  the release bundle (bnk-forge ${FORGE_VERSION}, dist/)"
[[ -d "$SRC/.git" ]] || git -c advice.detachedHead=false clone -q --depth 1 --branch "$FORGE_REF" https://github.com/iracic82/bnk-forge.git "$SRC"
mkdir -p "$DST"; cp -r "$SRC/dist/." "$DST/"
ok "$DST: $(ls "$DST" | paste -sd' ' -)"

step "2/6  .env: images, passwords, the first admin password"
cd "$DST" || exit 1
[[ -f .env ]] || cp .env.example .env
setv() { if grep -qE "^#? *$1=" .env; then sed -i "s|^#\? *$1=.*|$1=$2|" .env; else echo "$1=$2" >> .env; fi; }
setv BNK_FORGE_REGISTRY ghcr.io/f5devcentral
setv BNK_FORGE_VERSION "$FORGE_VERSION"
setv POSTGRES_PASSWORD "$(lab_secret forge-postgres)"
setv REDIS_PASSWORD "$(lab_secret forge-redis)"
setv MCP_SERVICE_PASSWORD "$(lab_secret forge-mcp)"
setv DEFAULT_ADMIN_PASSWORD "$(lab_secret forge-initial)"
setv ARTIFACT_NETWORK_SUBNET 10.200.0.0/24
chmod 600 .env
ok "images from ghcr.io/f5devcentral at ${FORGE_VERSION}; strong per-sandbox database passwords"

step "3/6  ./install.sh (pulls ~8 images on first run, a few minutes)"
# Forge's own installer, its output kept in full (a filtered view once hid the reason it stopped).
log=/root/.lab/forge-install.log
# bash, not ./install.sh: the bundle in the fork is not marked executable
if ! bash ./install.sh > "$log" 2>&1; then
  tail -30 "$log" | sed 's/^/      /'
  fail "Forge's install.sh failed (full log: $log)"
fi
grep -E '✓|✅|⚠|healthy|Installation' "$log" | sed 's/^/      /' || true
for _ in $(seq 1 120); do curl -fsSk https://127.0.0.1/api/health >/dev/null 2>&1 && break; sleep 5; done
curl -fsSk https://127.0.0.1/api/health >/dev/null || fail "Forge did not become healthy: docker compose -f $DST/docker-compose.yml ps"
ok "Forge healthy behind its TLS proxy on :443"

step "4/6  first login: Forge forces a password change, so do it now"
tok=$(curl -fsSk -X POST https://127.0.0.1/api/auth/login -H 'Content-Type: application/json' \
       --data "{\"username\":\"admin\",\"password\":\"$(lab_secret forge-initial)\"}" | jq -r '.token // empty' || true)
if [[ -n "$tok" ]]; then
  curl -fsSk -X POST https://127.0.0.1/api/auth/change-password -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' \
    --data "{\"current_password\":\"$(lab_secret forge-initial)\",\"new_password\":\"$(lab_secret forge-password)\"}" -o /dev/null \
    || warn "password change refused (already changed?)"
fi
forge_api GET /api/auth/me >/dev/null || fail "cannot log in to Forge as admin"
ok "admin / $(lab_secret forge-password)   (also in /root/.lab/forge-password)"

step "5/6  supply chain: allow the lab registry"
# Forge only runs container images from allowlisted registries, pinned by digest. Add the lab's.
forge_api PUT "/api/system/defaults/container.registry_host_allowlist?value=ghcr.io,quay.io,docker.io,registry.k8s.io,localhost:${PORT_REGISTRY}" >/dev/null
ok "container.registry_host_allowlist now includes localhost:${PORT_REGISTRY}"

step "6/6  a plain-HTTP door for the Instruqt tab (:${PORT_FORGE_TAB} -> https://127.0.0.1:443)"
mkdir -p /root/.lab/forge-tab
cat > /root/.lab/forge-tab/nginx.conf <<NGX
events {}
http {
  map \$http_upgrade \$conn { default upgrade; '' close; }
  server {
    listen ${PORT_FORGE_TAB};
    client_max_body_size 50m;
    location / {
      proxy_pass https://127.0.0.1:443;
      proxy_ssl_verify off;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$conn;
      proxy_set_header Host \$host;
      proxy_set_header X-Forwarded-Proto https;
      proxy_read_timeout 3600s;
    }
  }
}
NGX
docker rm -f forge-tab >/dev/null 2>&1 || true
docker run -d --name forge-tab --restart unless-stopped --network host -v /root/.lab/forge-tab/nginx.conf:/etc/nginx/nginx.conf:ro nginx:1.27-alpine >/dev/null
for _ in $(seq 1 20); do curl -fsS -o /dev/null "http://127.0.0.1:${PORT_FORGE_TAB}/" && break; sleep 1; done
ok "open the BNK Forge tab and sign in as admin"
set_owner forge
