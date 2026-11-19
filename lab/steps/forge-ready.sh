#!/usr/bin/env bash
# lab forge-ready: make Forge ready to operate this cluster, whatever installed BNK.
# Installs Forge if it is missing (without taking ownership of installs), then registers cluster 'lab'.
# Safe to run any number of times.
source "$(dirname "$0")/../lib.sh"
if curl -fsSk -o /dev/null https://127.0.0.1:8443/api/system/health; then
  ok "Forge already running"
else
  step "installing Forge as the operations tool"
  LAB_KEEP_OWNER=1 bash "$(dirname "$0")/forge.sh"
fi
bash "$(dirname "$0")/forge-register.sh"
