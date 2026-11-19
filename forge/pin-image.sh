#!/usr/bin/env bash
# Pins the runner image Forge runs, by digest, in forge/bnk-host/bnkforge.artifact.json.
# Forge refuses floating tags: the digest is the proof of exactly which build of the installer runs.
#   forge/pin-image.sh <registry_host> <repository> <sha256:digest>
#   forge/pin-image.sh localhost:5000 bnk-host-deploy sha256:9f2c...
set -euo pipefail
f="$(dirname "$0")/bnk-host/bnkforge.artifact.json"
[[ "${3:-}" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "usage: $0 <registry_host> <repository> <sha256:64hex>"; exit 2; }
jq --arg h "$1" --arg r "$2" --arg d "$3" \
  '.container_image = {registry_host:$h, repository:$r, digest:$d}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
echo "pinned $1/$2@$3"
