#!/usr/bin/env bash
# lab image: build the installer's runner image from your working copy, push it to the lab registry
# and pin its digest where Forge and Argo CD read it. On GitHub the image workflow does exactly this
# on a release tag (with GHCR instead of the lab registry).
#
#   localhost:5000   how the VM's Docker, and so BNK Forge, pulls it
#   172.18.0.1:5000  how the kind nodes, and so the Argo CD install Job, pull it
source "$(dirname "$0")/../lib.sh"
WS="${WORKSPACE:-/root/workspace/bnk-host-deploy}"
[[ -d "$WS/.git" ]] || fail "no working copy at $WS"
# shellcheck source=versions.env
source "$WS/versions.env"

step "1/4  the lab registry (a plain registry:2, like a tiny Harbor or GHCR)"
if ! docker ps --format '{{.Names}}' | grep -qx lab-registry; then
  docker rm -f lab-registry >/dev/null 2>&1 || true
  docker run -d --name lab-registry --restart unless-stopped -v /var/lib/lab-registry:/var/lib/registry \
    -p "127.0.0.1:${PORT_REGISTRY}:5000" -p "172.18.0.1:${PORT_REGISTRY}:5000" "$REGISTRY_IMAGE" >/dev/null
fi
for _ in $(seq 1 30); do curl -fsS "http://127.0.0.1:${PORT_REGISTRY}/v2/" >/dev/null 2>&1 && break; sleep 1; done
ok "registry answering on 127.0.0.1:${PORT_REGISTRY} and 172.18.0.1:${PORT_REGISTRY}"

rev="$(git -C "$WS" rev-parse --short HEAD)"
TAG="localhost:${PORT_REGISTRY}/bnk-host-deploy:${BNK_VERSION}-${rev}"
step "2/4  docker build: installer + pinned kubectl ${KUBECTL_VERSION}, helm ${HELM_VERSION}, yq ${YQ_VERSION}"
docker build -t "$TAG" --build-arg "KUBECTL_VERSION=$KUBECTL_VERSION" --build-arg "HELM_VERSION=$HELM_VERSION" \
  --build-arg "YQ_VERSION=$YQ_VERSION" --build-arg "GIT_COMMIT=$(git -C "$WS" rev-parse HEAD)$([[ -n "$(git -C "$WS" status --porcelain)" ]] && echo -dirty)" "$WS" 2>&1 | grep -E '^#[0-9]+ (\[|DONE|naming)' | tail -12 || true
docker image inspect "$TAG" >/dev/null 2>&1 || fail "docker build did not produce $TAG"
[[ -n "$(git -C "$WS" status --porcelain)" ]] && echo "      note: built from uncommitted changes; provenance will say <commit>-dirty. Commit first for a clean stamp."
docker run --rm "$TAG" version | sed 's/^/      /'
ok "image runs as uid $(docker run --rm --entrypoint id "$TAG" -u), the non-root user Forge insists on"

step "3/4  push, and read back the digest (the content hash: unlike a tag, it cannot move)"
docker push -q "$TAG" >/dev/null
DIGEST=$(docker inspect --format '{{index .RepoDigests 0}}' "$TAG" | sed 's/.*@//')
[[ "$DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "no digest for $TAG"
echo "$DIGEST" > "$LAB_STATE/runner-digest"
ok "$TAG"
ok "digest $DIGEST"

step "4/4  pin the digest in the repository"
# A different build is a new release in Forge's catalog (versions there are immutable): bump the patch.
art="$WS/forge/bnk-host/bnkforge.artifact.json"
cur_digest=$(jq -r '.container_image.digest' "$art"); cur_ver=$(jq -r '.version' "$art")
newver=""
if [[ "$cur_digest" != "$DIGEST" && "$cur_digest" != sha256:0000000000000000000000000000000000000000000000000000000000000000 ]]; then
  newver="${cur_ver%.*}.$(( ${cur_ver##*.} + 1 ))"
fi
"$WS/forge/pin-image.sh" "localhost:${PORT_REGISTRY}" bnk-host-deploy "$DIGEST" $newver | sed 's/^/      forge:  /'
"$WS/argocd/pin-image.sh" "172.18.0.1:${PORT_REGISTRY}/bnk-host-deploy@${DIGEST}" | sed 's/^/      argocd: /'
echo
git -C "$WS" --no-pager diff --stat
echo
echo "   Next: commit the pin and merge it, so Forge and Argo CD run exactly this build."
