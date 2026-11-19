#!/usr/bin/env bash
# Pins the runner image the Argo CD install Job runs: argocd/pin-image.sh <registry/repo@sha256:digest>
set -euo pipefail
f="$(dirname "$0")/bnk-install/job.yaml"
[[ "${1:-}" =~ @sha256:[0-9a-f]{64}$ ]] || { echo "usage: $0 <image@sha256:64hex>"; exit 2; }
yq -i ".spec.template.spec.containers[0].image = \"$1\"" "$f"
echo "pinned $1"
