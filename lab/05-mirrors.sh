#!/usr/bin/env bash
# Pull-through registry mirrors, one per upstream registry, so the kind nodes pull every image once.
# The f5/aibnk VM image ships /var/lib/bnk-mirrors already filled (BNK 2.4.x, Calico, cert-manager,
# Multus), so most pulls at track start come from local disk. Nothing to maintain: whatever an
# install pulls is cached. repo.f5.com needs the FAR key; it reaches the mirror as a mounted config
# file that is shredded once the registry has read it.
source "$(dirname "$0")/lib.sh"
need docker
MIRROR_DIR="${MIRROR_DIR:-/var/lib/bnk-mirrors}"
declare -A MIRRORS=( [docker.io]=5001 [quay.io]=5002 [ghcr.io]=5003 [registry.k8s.io]=5004 [repo.f5.com]=5006 [gcr.io]=5007 )
remote() { case "$1" in docker.io) echo https://registry-1.docker.io ;; *) echo "https://$1" ;; esac; }

# The kind network, pinned, so every address in clusters/lab.network.yaml is stable. Docker hands out
# addresses from the lower half only; .250 stays free for TMM's internal self IP.
if ! docker network inspect kind >/dev/null 2>&1; then
  docker network create kind --subnet 172.18.0.0/16 --gateway 172.18.0.1 --ip-range 172.18.0.0/25 \
    -o com.docker.network.bridge.enable_ip_masquerade=true >/dev/null
fi
[[ "$(docker network inspect kind -f '{{(index .IPAM.Config 0).Subnet}}')" == 172.18.0.0/16 ]] \
  || fail "docker network kind exists with another subnet; remove it (no cluster yet) and re-run"
BIND_IP=172.18.0.1
mkdir -p "$MIRROR_DIR"; echo "$BIND_IP" > "$MIRROR_DIR/.bind"

step "registry mirrors on $BIND_IP"
for up in "${!MIRRORS[@]}"; do
  port=${MIRRORS[$up]}; name="mirror-${up//./-}"
  args=(-v "$MIRROR_DIR/$up:/var/lib/registry"); cfg=""
  if [[ "$up" == repo.f5.com ]]; then
    f="$SECRETS_DIR/cne_pull_64.json"; [[ -r "$f" ]] || fail "$f missing (needed by the repo.f5.com mirror)"
    cfg=$(mktemp -p "$SECRETS_DIR" mirror-XXXXXX.yml); chmod 600 "$cfg"
    python3 - "$f" "$cfg" "$(remote "$up")" <<'PY'
import sys, json
far, cfg, url = sys.argv[1:]
pw = open(far).read().strip()
open(cfg, 'w').write("version: 0.1\nlog:\n  level: warn\nstorage:\n  filesystem:\n    rootdirectory: /var/lib/registry\n  delete:\n    enabled: true\n"
                     "http:\n  addr: :5000\n" f"proxy:\n  remoteurl: {url}\n  username: _json_key_base64\n  password: {json.dumps(pw)}\n")
PY
    args+=(-v "$cfg:/etc/docker/registry/config.yml:ro")
  else
    args+=(-e "REGISTRY_PROXY_REMOTEURL=$(remote "$up")")
  fi
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker run -d --name "$name" --restart unless-stopped -p "$BIND_IP:$port:5000" "${args[@]}" "$REGISTRY_IMAGE" >/dev/null
  code=000
  for _ in $(seq 1 30); do code=$(curl -s -o /dev/null -w '%{http_code}' "http://$BIND_IP:$port/v2/" || true); [[ "$code" == 200 ]] && break; sleep 1; done
  [[ -n "$cfg" ]] && { shred -u "$cfg" 2>/dev/null || rm -f "$cfg"; }
  [[ "$code" == 200 ]] && ok "$up -> $BIND_IP:$port" || warn "$up mirror answered $code"
done
du -sh "$MIRROR_DIR" 2>/dev/null | sed 's/^/   cache: /'

step "the VM's own Docker pulls Docker Hub images through the mirror too"
# Many sandboxes start at once from the same few addresses; anonymous Docker Hub pulls are rate
# limited. Gitea, nginx, FRR and netshoot then come from the baked cache. A mirror that is down is
# skipped by Docker, so this never blocks a pull.
cfg=/etc/docker/daemon.json; [[ -s "$cfg" ]] || echo '{}' > "$cfg"
if ! jq -e '.["registry-mirrors"] // [] | index("http://172.18.0.1:5001")' "$cfg" >/dev/null; then
  jq '.["registry-mirrors"] = ((.["registry-mirrors"] // []) + ["http://172.18.0.1:5001"] | unique)' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
  systemctl restart docker
  for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
fi
ok "docker.io pulls go through http://172.18.0.1:5001 first"
