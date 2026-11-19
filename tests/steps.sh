#!/usr/bin/env bash
# Forge (and anyone else) drives the installer one step at a time through bin/bnk-host. Every phase
# install.sh runs must belong to exactly one of those steps, or a step-by-step install silently skips
# it. (Phase 45 was once missing: FLO waited forever for its NetworkAttachmentDefinitions.)
set -euo pipefail
cd "$(dirname "$0")/.."
mapfile -t all < <(sed -n '/^PHASES=(/,/^)/p' install.sh | grep -oE '^\s+"[0-9]{2}' | tr -dc '0-9\n')
mapfile -t steps < <(sed -n '/^case /,/^esac/p' bin/bnk-host | grep -oE 'phase [0-9]{2}' | awk '{print $2}')
rc=0
for p in "${all[@]}"; do
  n=$(printf '%s\n' "${steps[@]}" | grep -cx "$p" || true)
  [[ "$n" == 1 ]] || { echo "phase $p is in $n bin/bnk-host steps (want exactly 1)"; rc=1; }
done
for s in "${steps[@]}"; do printf '%s\n' "${all[@]}" | grep -qx "$s" || { echo "bin/bnk-host runs phase $s, which install.sh does not have"; rc=1; }; done
[[ $rc == 0 ]] && echo "steps: all ${#all[@]} installer phases covered once by bin/bnk-host"
exit $rc
