#!/usr/bin/env bash
# Which cluster files does a change affect? Prints one path per line.
#
#   ci/targets.sh <base-ref> <head-ref>     clusters affected by the diff base..head
#   ci/targets.sh --all                     every enabled cluster
#
# Rules, in order:
#   - a change to how BNK is installed (versions.env, install.sh, lib/, profiles/) affects every
#     enabled cluster: they all run that code
#   - a change to environments/<env>.env affects the enabled clusters in that environment
#   - a change to clusters/<name>.yaml affects that cluster (enabled or not: the plan should show
#     a cluster being switched off, and deploy skips disabled ones)
# Anything else (docs, the Forge module, the lab) affects no cluster, so no runner is woken up.
set -euo pipefail
cd "$(dirname "$0")/.."

enabled() { for f in clusters/*.yaml; do [[ "$(basename "$f" .yaml)" == *.* ]] && continue; [[ "$(yq -r '.enabled // false' "$f")" == "true" ]] && echo "$f"; done; return 0; }

if [[ "${1:-}" == "--all" ]]; then enabled; exit 0; fi
base="${1:?base ref}"; head="${2:?head ref}"

# A first push has no usable base (all zeros); treat it as "everything changed".
if [[ "$base" =~ ^0+$ ]] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then enabled; exit 0; fi

changed="$(git diff --name-only "$base" "$head")"
{
  if grep -qE '^(versions\.env|install\.sh|lib/|profiles/)' <<<"$changed"; then enabled; fi
  while IFS= read -r e; do
    [[ -n "$e" ]] || continue
    env="$(basename "$e" .env)"
    for f in clusters/*.yaml; do
      [[ "$(basename "$f" .yaml)" == *.* ]] && continue
      [[ "$(yq -r '.environment' "$f")" == "$env" && "$(yq -r '.enabled // false' "$f")" == "true" ]] && echo "$f"
    done
  done < <(grep -E '^environments/[^/]+\.env$' <<<"$changed" || true)
  while IFS= read -r c; do
    [[ -n "$c" && -f "$c" ]] && echo "$c"
  done < <(grep -E '^clusters/[^/.]+(\.[a-z]+)?\.yaml$' <<<"$changed" | sed -E 's#^(clusters/[^/.]+)\.[a-z]+\.yaml$#\1.yaml#' || true)
} | sort -u
