# shellcheck shell=bash
# Shared by the lab build scripts (lab/NN-*.sh). These build the training VM: a Kubernetes cluster
# with no BNK on it, plus the tools a platform team would already have (a git server with CI, an
# editor, BNK Forge). They are not part of the product; the product is everything outside lab/.
# Settings below are read by the scripts that source this file.
# shellcheck disable=SC2034
set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/.local/bin"
export HOME="${HOME:-/root}"

LAB_REPO_DIR="${LAB_REPO_DIR:-/root/bnk-host-deploy}"      # pristine checkout the lab scripts run from
WORKSPACE="${WORKSPACE:-/root/workspace/bnk-host-deploy}" # the learner's clone (from Gitea), open in VS Code
LAB_STATE="${LAB_STATE:-/root/.lab}"                       # lab-only state: passwords, tokens
SECRETS_DIR="${SECRETS_DIR:-/root/.bnk}"                   # FAR key + licence, shredded after setup
mkdir -p "$LAB_STATE"; chmod 700 "$LAB_STATE"

# Versions of the lab's own scaffolding (the product's pins live in versions.env).
KIND_NODE_IMAGE="kindest/node:v1.35.5@sha256:ce977ae6d65918d0b58a5f8b5e940429c2ce42fa3a5619ec2bbc60b949c0ac95"
KIND_CLUSTER=bnk
NR_HUGEPAGES=2048                 # 4 GiB of 2Mi pages: TMM requests 2 GiB
GITEA_IMAGE="gitea/gitea:1.27.3"
GITEA_RUNNER_VERSION="6.0.0"     # needs Gitea >= 1.26.2; runs .github/workflows unchanged
SHELLCHECK_VERSION=v0.10.0
SHELLCHECK_SHA256=6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87
NODE_VERSION="v22.21.1"           # host-mode jobs run JavaScript actions (actions/checkout) with it
CODE_SERVER_VERSION="4.105.1"
FORGE_REF="v4.3.4"                # bnk-forge release tag that carries dist/ (install bundle)
FORGE_REPO="https://github.com/JLCode-tech/bnk-forge.git"
FORGE_REGISTRY="ghcr.io/jlcode-tech"    # where this release's images are published (ghcr.io/<repo owner>)
# 4.3.4's Celery images (api, worker, beat) were built with an unpinned kombu 5.7.0, which refuses its own
# redis-py 5.2.1, so no job can be queued and Deploy all fails with HTTP 500. lab forge builds a one-line
# fix on top of the verified originals: kombu pinned to 5.5.4 (celery 5.4.0 accepts it, pip check is clean).
FORGE_KOMBU_FIX="kombu==5.5.4"
FORGE_PATCH_IMAGES="bnk-forge-api bnk-forge-worker bnk-forge-beat"
# The tag and the images live in a third-party namespace, and tags can move. Pin the content: the commit
# the tag pointed at when this lab was checked, and each image's digest. lab forge refuses anything else.
FORGE_COMMIT="1a9239d6aa8793d30c7fbf9c76f816206b05d4a8"
FORGE_IMAGE_DIGESTS="bnk-forge-api@sha256:bfc042e4111d243885b752cdbcc3cf5f3555398f49a14fe14e90a52051057638
bnk-forge-beat@sha256:54d7802b14935442bd777984a033a1693cfe14cb0edaa3dda8c459ce021a4ae5
bnk-forge-frontend@sha256:9aa2cbaf3e104707f776be61375f4eba14535dd1e5941c937d5306744f10e7e5
bnk-forge-mcp@sha256:c179a9743411418bad828b7dad5a7aea4a1870d856fc1375a7a3e73d883c4b37
bnk-forge-proxy@sha256:9e2f345c2f04c62f5ddfc840f6e6877d710fe5bae560b55055ee00ae5da80573
bnk-forge-worker@sha256:9667337660d46626ad456cbc3fb98b221f1e3c4da2c0b0ab383b9618f2f71a71"
REGISTRY_IMAGE="registry:2.8.3"

# Ports on the VM. Instruqt tabs connect to these.
PORT_GITEA=3000
PORT_CODE=8444
PORT_FORGE_TAB=8090               # plain-HTTP front for Forge's TLS proxy on :8443 (Instruqt tabs want HTTP)
PORT_TOPOLOGY=5050
PORT_INFERENCE=5060
PORT_REGISTRY=5000
PORT_ARGOCD=8091
FRR_IMAGE="quay.io/frrouting/frr:10.6.2"
CLIENT_IMAGE="nicolaka/netshoot:v0.14"
FORGE_VERSION="4.3.4"
ARGOCD_VERSION="v3.6.2"

LAB_USER=learner                  # the Gitea account the learner works as
GITEA_ORG=platform
GITEA_REPO=bnk-host-deploy

vm_ip() { ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1; }

step() { printf '\n### %s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
ok()   { printf '   ok  %s\n' "$*"; }
warn() { printf '   !!  %s\n' "$*"; }
fail() { printf '   FAIL %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "$1 is not installed"; }

# A password generated once per sandbox and remembered, so re-running a script is harmless.
lab_secret() {  # lab_secret <name>
  local f="$LAB_STATE/$1"
  [[ -s "$f" ]] || { (umask 077; tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 > "$f"); }
  cat "$f"
}

# Gitea API as the learner (basic auth; the token is created in 20-gitea.sh).
gitea_api() {  # gitea_api <method> <path> [json]
  local m="$1" p="$2" d="${3:-}"
  curl -fsS -X "$m" -u "${LAB_USER}:$(lab_secret gitea-password)" -H 'Content-Type: application/json' \
    ${d:+--data "$d"} "http://127.0.0.1:${PORT_GITEA}/api/v1${p}"
}

# Forge API. Logs in once per script and caches the token. Forge allows 100 requests a minute per
# client address, and the Forge tab in the browser shares this VM's address, so 429 is retried with a
# growing pause (or Forge's Retry-After). Any other failure prints Forge's own error body.
#   forge_api <method> <path> [json | @-]      (@- reads the body from stdin)
_forge_req() {  # _forge_req <method> <url> <body-file|""> [auth header]
  local m="$1" url="$2" bf="$3" auth="${4:-}" out code ra i
  out=$(mktemp)
  for i in 1 2 3 4 5 6 7 8; do
    code=$(curl -sSk -o "$out" -D "$out.h" -w '%{http_code}' -X "$m" -H 'Content-Type: application/json' \
             ${auth:+-H "$auth"} ${bf:+--data-binary "@$bf"} "$url") || code=000
    if [[ "$code" == 429 ]]; then
      ra=$(sed -n 's/^[Rr]etry-[Aa]fter: *\([0-9]*\).*/\1/p' "$out.h" | head -1)
      sleep "${ra:-$(( i * 5 ))}"; continue
    fi
    break
  done
  if [[ "$code" =~ ^2 ]]; then cat "$out"; rm -f "$out" "$out.h"; return 0; fi
  echo "Forge answered $code for $m ${url#https://127.0.0.1:8443}: $(head -c 400 "$out")" >&2
  rm -f "$out" "$out.h"; return 1
}
forge_api() {
  local m="$1" p="$2" d="${3:-}" bf=""
  if [[ -z "${_FORGE_TOKEN:-}" ]]; then
    local lf; lf=$(mktemp); printf '{"username":"admin","password":"%s"}' "$(lab_secret forge-password)" > "$lf"
    _FORGE_TOKEN=$(_forge_req POST https://127.0.0.1:8443/api/auth/login "$lf" | jq -r '.token // empty'); rm -f "$lf"
    [[ -n "$_FORGE_TOKEN" ]] || fail "cannot log in to Forge as admin"
  fi
  if [[ "$d" == "@-" ]]; then bf=$(mktemp); chmod 600 "$bf"; cat > "$bf"
  elif [[ -n "$d" ]]; then bf=$(mktemp); printf '%s' "$d" > "$bf"; fi
  local rc=0; _forge_req "$m" "https://127.0.0.1:8443${p}" "$bf" "Authorization: Bearer $_FORGE_TOKEN" || rc=$?
  [[ -n "$bf" ]] && { shred -u "$bf" 2>/dev/null || rm -f "$bf"; }
  return $rc
}

# Read one value from the lab vault, for piping into another secret store. Never echo the result.
vault_get() {  # vault_get far_service_account_key|bnk_license_jwt
  kubectl -n lab-vault get secret bnk-credentials -o "jsonpath={.data.$1}" | base64 -d
}

# Declare which orchestrator owns BNK installs for this repository (repository variable BNK_INSTALLER).
set_owner() {  # set_owner pipeline|forge|argocd
  local r="/repos/${GITEA_ORG}/${GITEA_REPO}/actions/variables/BNK_INSTALLER"
  gitea_api PUT "$r" "{\"value\":\"$1\"}" >/dev/null 2>&1 || gitea_api POST "$r" "{\"value\":\"$1\"}" >/dev/null
  ok "repository variable BNK_INSTALLER=$1: only $1 installs BNK on this cluster"
}

# Unpack .xz and .tar.xz with Python's standard library, so the lab needs no xz package (no apt at all).
unxz_to() {  # unxz_to <file.xz> <output file>
  python3 -c 'import lzma,shutil,sys; shutil.copyfileobj(lzma.open(sys.argv[1]), open(sys.argv[2],"wb"))' "$1" "$2"
}
untar_xz() {  # untar_xz <file.tar.xz> <dir> [strip-components]
  python3 - "$1" "$2" "${3:-0}" <<'PY'
import os, sys, tarfile
src, dst, strip = sys.argv[1], sys.argv[2], int(sys.argv[3])
with tarfile.open(src, "r:xz") as t:
    for m in t.getmembers():
        parts = m.name.split("/")[strip:]
        if not parts or not parts[0]:
            continue
        m.name = "/".join(parts)
        if m.islnk():
            m.linkname = "/".join(m.linkname.split("/")[strip:])
        t.extract(m, dst, filter="tar") if hasattr(tarfile, "data_filter") else t.extract(m, dst)
PY
}

