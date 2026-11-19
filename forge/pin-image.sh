#!/usr/bin/env bash
# Pins the runner image Forge runs, by digest, and (optionally) releases it as a new module version.
#   forge/pin-image.sh <registry_host> <repository> <sha256:digest> [version]
#
# Forge treats a catalog version as immutable: the same version with different content is refused as
# a version conflict. So a new digest normally comes with a new version, set consistently in the three
# places that carry it: the artifact, the pack, and the blueprint (its own version and its module pin).
set -euo pipefail
d="$(cd "$(dirname "$0")" && pwd)"
[[ "${3:-}" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "usage: $0 <registry_host> <repository> <sha256:64hex> [version]"; exit 2; }
art="$d/bnk-host/bnkforge.artifact.json"; pack="$d/bnk-host/bnkforge.pack.json"; bp="$d/forge-blueprint.json"
edit() { jq "${@:2}" "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
edit "$art" --arg h "$1" --arg r "$2" --arg g "$3" '.container_image = {registry_host:$h, repository:$r, digest:$g}'
echo "pinned $1/$2@$3"
if [[ -n "${4:-}" ]]; then
  edit "$art"  --arg v "$4" '.version = $v'
  edit "$pack" --arg v "$4" '.module.version = $v'
  edit "$bp"   --arg v "$4" '.blueprint.version = $v | .modules |= map(if .module == "forge/bnk-host" then .version = $v else . end)'
  echo "released as module and blueprint version $4"
fi
