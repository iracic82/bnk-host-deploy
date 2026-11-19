#!/usr/bin/env bash
# Validates cluster files with the same loader install.sh uses. With no arguments, every file.
#   ./tests/cluster.sh                     all clusters/*.yaml
#   ./tests/cluster.sh clusters/lab.yaml   one file
# Also runs the loader against fixtures that must be rejected, so the validation itself is tested.
set -euo pipefail
cd "$(dirname "$0")/.."
export HERE=$PWD
# shellcheck source=lib/cluster.sh
source lib/cluster.sh
command -v yq >/dev/null || { echo "yq is required (see versions.env YQ_VERSION)"; exit 2; }
files=("$@"); [[ ${#files[@]} -gt 0 ]] || for f in clusters/*.yaml; do [[ "$(basename "$f" .yaml)" == *.* ]] || files+=("$f"); done
rc=0
for f in "${files[@]}"; do
  if ( load_cluster "$f" ) ; then
    ( load_cluster "$f"; echo "ok    $f  env=$CLUSTER_ENV enabled=$CLUSTER_ENABLED tmm=${BNK_TMM_NODES:-<none>}" )
  else rc=1; fi
done
[[ $# -gt 0 ]] && exit $rc
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
bad() { local n=$1; shift; mkdir -p "$t/$n"; printf '%s\n' "$@" > "$t/$n/x.yaml"
        if ( load_cluster "$t/$n/x.yaml" ) 2>/dev/null; then echo "FAIL fixture '$n' was accepted"; rc=1; else echo "ok    rejects: $n"; fi; }
bad name-mismatch  'name: y' 'environment: lab' 'enabled: false'
bad no-env         'name: x' 'enabled: false'
bad unknown-env    'name: x' 'environment: moon' 'enabled: false'
bad enabled-no-tmm 'name: x' 'environment: lab' 'enabled: true'
bad two-tmm        'name: x' 'environment: lab' 'enabled: true' 'tmm: {nodes: [a, b]}'
bad enabled-typo   'name: x' 'environment: lab' 'enabled: yes please'
exit $rc
