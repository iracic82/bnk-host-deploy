#!/usr/bin/env bash
# lab status: one screen with the state of the lab.
source "$(dirname "$0")/../lib.sh"
touch "$LAB_STATE/seen-status"
row() { printf '  %-26s %s\n' "$1" "$2"; }
yes() { printf '\033[32m%s\033[0m' "$*"; }
no()  { printf '\033[33m%s\033[0m' "$*"; }
echo; echo "  Cluster"
row "nodes" "$(kubectl get nodes --no-headers 2>/dev/null | awk '{printf "%s(%s) ", $1, $2}')"
row "TMM node label" "$(kubectl get nodes -l app=f5-tmm -o name 2>/dev/null | cut -d/ -f2 | paste -sd, - | sed 's/^$/none yet/')"
echo; echo "  BIG-IP Next for Kubernetes"
flo=$(kubectl -n f5-cne-core get deploy f5-lifecycle-operator -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
row "lifecycle operator (FLO)" "$([[ "${flo:-0}" -ge 1 ]] && yes running || no 'not installed')"
cne=$(kubectl -n f5-bnk get cneinstance f5-bnk-instance -o jsonpath='{.spec.manifestVersion} Available={.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)
row "CNEInstance" "${cne:-$(no 'not installed')}"
lic=$(kubectl -n f5-cne-core get license.k8s.f5net.com -o jsonpath='{.items[0].status.state}' 2>/dev/null || true)
row "licence" "${lic:-$(no 'none')}"
row "TMM" "$(kubectl -n f5-bnk get ds f5-tmm -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled} ready' 2>/dev/null || echo -)"
row "GatewayClass" "$(kubectl get gatewayclass -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Accepted")].status} {end}' 2>/dev/null || echo -)"
row "Gateways" "$(kubectl get gateway -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}@{.status.addresses[0].value} {end}' 2>/dev/null || echo -)"
echo; echo "  Tooling"
row "Gitea runner" "$(systemctl is-active gitea-runner 2>/dev/null | sed 's/^inactive$/not registered/')"
row "CI secrets" "$(gitea_api GET "/repos/${GITEA_ORG}/${GITEA_REPO}/actions/secrets" 2>/dev/null | jq -r '[.[].name]|join(", ")' | sed 's/^$/none/')"
row "BNK Forge" "$(curl -fsSk -o /dev/null https://127.0.0.1:8443/api/system/health 2>/dev/null && echo running || echo 'not installed')"
row "Argo CD" "$(kubectl -n argocd get applications -o jsonpath='{range .items[*]}{.metadata.name}:{.status.sync.status}/{.status.health.status} {end}' 2>/dev/null || echo 'not installed')"
row "edge router / client" "$(docker ps --format '{{.Names}}' | grep -cE '^(edge-router|client)$')/2 running"
echo
