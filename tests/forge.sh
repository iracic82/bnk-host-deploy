#!/usr/bin/env bash
# Validates forge/ (the module pack, its artifact manifest, the blueprint) with BNK Forge's own
# catalog validator, the same code Forge runs when it syncs this repository as a module source.
# Clones bnk-forge at a pinned tag into a cache and runs it in a throwaway virtualenv.
set -euo pipefail
cd "$(dirname "$0")/.."
FORGE_REF="${FORGE_REF:-v4.3.4}"; FORGE_REPO="${FORGE_REPO:-https://github.com/JLCode-tech/bnk-forge.git}"; CACHE="${FORGE_CACHE:-${RUNNER_TEMP:-/tmp}/bnk-forge-validator}"
[[ -d "$CACHE/src/.git" ]] || git -c advice.detachedHead=false clone -q --depth 1 --branch "$FORGE_REF" "$FORGE_REPO" "$CACHE/src"
FORGE_COMMIT="${FORGE_COMMIT:-1a9239d6aa8793d30c7fbf9c76f816206b05d4a8}"   # v4.3.4, as checked
[[ "$(git -C "$CACHE/src" rev-parse HEAD)" == "$FORGE_COMMIT" ]] || { echo "bnk-forge $FORGE_REF is not the pinned commit $FORGE_COMMIT"; exit 1; }
if [[ ! -x "$CACHE/venv/bin/python" ]]; then
  python3 -m venv "$CACHE/venv" 2>/dev/null || { apt-get install -y -qq python3-venv >/dev/null 2>&1 && python3 -m venv "$CACHE/venv"; }
  "$CACHE/venv/bin/pip" install -q pydantic pydantic-settings sqlalchemy cryptography "psycopg[binary]"
fi
# The validator imports Forge's backend, which wants a database URL it never connects to.
cd "$CACHE/src"
DATABASE_URL=postgresql+psycopg://x:y@127.0.0.1:1/x "$CACHE/venv/bin/python" scripts/validate_catalog_content.py \
  "$OLDPWD" --registry-allowlist "ghcr.io,quay.io,docker.io,registry.k8s.io,localhost:5000" 2>&1 \
  | grep -vE 'persist|in-memory|Fix with' 
