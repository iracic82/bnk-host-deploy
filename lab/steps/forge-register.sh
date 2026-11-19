#!/usr/bin/env bash
# lab forge-register: register the running cluster in Forge for Day-2, whoever installed BNK.
# Forge does not need to have installed BNK to operate it: give it a kubeconfig and it reads the
# cluster's BNK objects (versions, health, gateways, licence), takes snapshots and detects drift.
source "$(dirname "$0")/../lib.sh"
curl -fsSk -o /dev/null https://127.0.0.1:8443/api/system/health || fail "Forge is not installed: run 'lab forge' first"
existing=$(forge_api GET /api/k8s/clusters | jq -r '(if type=="array" then . else (.items // .sources // .projects // .clusters // .modules // .secrets // []) end)[] | select(.name=="lab") | .id' | head -1)
if [[ -n "$existing" ]]; then ok "cluster 'lab' already registered (#$existing)"; exit 0; fi
pid=$(forge_api GET /api/projects | jq -r '(if type=="array" then . else (.items // .sources // .projects // .clusters // .modules // .secrets // []) end)[] | select(.name=="operations" or .name=="bnk-lab") | .id' | head -1)
if [[ -z "$pid" ]]; then
  pid=$(forge_api POST /api/projects '{"name":"operations","description":"Day-2 operations for the lab cluster","environment":"lab"}' | jq -r '.id // .project.id // .project_id')
  ok "project 'operations' (#$pid) created"
fi
kc=$(base64 -w0 /root/.lab/kubeconfig-forge.yaml)
jq -n --arg k "$kc" '{name:"lab", kubeconfig:$k, cloud_provider:"on-prem", default_namespace:"f5-bnk"}' \
  | curl -fsSk -X POST -H "Authorization: Bearer ${_FORGE_TOKEN}" -H 'Content-Type: application/json' \
      --data @- "https://127.0.0.1:8443/api/projects/${pid}/k8s/clusters" | jq -r '"   registered cluster \(.name) #\(.id): \(.api_server // "")"'
ok "Operate > Kubernetes > lab"
