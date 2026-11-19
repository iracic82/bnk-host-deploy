#!/usr/bin/env bash
# Static checks: shell syntax + shellcheck, YAML and JSON well-formedness. No cluster needed.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
for t in yq jq; do command -v $t >/dev/null || { echo "$t is required"; exit 2; }; done
mapfile -t sh < <(git ls-files '*.sh' 'bin/*' 'lab/lab' 'instruqt/**/track_scripts/*' 'instruqt/**/check-lab' 'instruqt/**/solve-lab' 2>/dev/null | sort -u)
for f in "${sh[@]}"; do
  [[ -f "$f" ]] || continue
  head -1 "$f" | grep -qE 'bash|sh' || grep -q 'shellcheck shell=' "$f" || continue
  bash -n "$f" || { echo "syntax: $f"; fail=1; }
done
if command -v shellcheck >/dev/null; then
  shellcheck -x -S warning "${sh[@]}" || fail=1
else
  echo "shellcheck not installed, skipping (CI installs it)"
fi
while IFS= read -r f; do yq -e '.' "$f" >/dev/null || { echo "bad YAML: $f"; fail=1; }; done \
  < <(git ls-files '*.yaml' '*.yml' | grep -v '^profiles/')
while IFS= read -r f; do jq -e . "$f" >/dev/null || { echo "bad JSON: $f"; fail=1; }; done < <(git ls-files '*.json')
# Forge manifests stay in jq's canonical layout, so pinning an image digest is a one-line diff.
for f in forge/*/*.json forge/*.json; do
  [[ "$(jq . "$f")" == "$(cat "$f")" ]] || { echo "not canonical JSON (run: jq . $f): $f"; fail=1; }
done
[[ $fail == 0 ]] && echo "lint: ok"
exit $fail
