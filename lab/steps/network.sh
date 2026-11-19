#!/usr/bin/env bash
# lab network: build the data-center edge BNK will serve, from a topology file, with containerlab.
#
#   client eth1 ---- eth2 edge-router eth1 ---- eth1 bnk-worker
#   10.20.20.10      .254   (FRR)    .254       (TMM's external leg: TMM takes 10.10.10.11)
#
# containerlab turns /opt/lab/edge/edge.clab.yml into containers and cables (veth pairs). The router's
# whole configuration is /opt/lab/edge/edge-router/frr.conf. Change the files, redeploy, and the network
# changes: the edge is code, like the cluster.
source "$(dirname "$0")/../lib.sh"
TOPO=/opt/lab/edge/edge.clab.yml

step "1/4  the topology file"
sed -n '/^topology:/,$p' "$TOPO" | grep -vE '^\s*#' | sed 's/^/      /'

step "2/4  containerlab deploy"
cd "$(dirname "$TOPO")" || exit 1
# "Deployed" means deployed by containerlab from this file. A router or client built some other way
# (an older version of this lab) is replaced, so the cables match the file.
if [[ "$(docker inspect -f '{{index .Config.Labels "containerlab"}}' edge-router 2>/dev/null)" == edge ]] \
   && docker exec bnk-worker ip link show eth1 >/dev/null 2>&1; then
  ok "already deployed by containerlab (containerlab destroy -t $TOPO to start over)"
else
  for c in edge-router client; do
    if docker inspect "$c" >/dev/null 2>&1 && [[ "$(docker inspect -f '{{index .Config.Labels "containerlab"}}' "$c")" != edge ]]; then
      docker rm -f "$c" >/dev/null; ok "removed a $c that containerlab did not build"
    fi
  done
  for n in dc-edge client-net; do docker network rm "$n" >/dev/null 2>&1 && ok "removed the old docker network $n" || true; done
  containerlab deploy -t "$TOPO" 2>&1 | grep -E 'INFO|WARN|ERRO' | sed 's/^/      /' | tail -12
fi
containerlab inspect -t "$TOPO" 2>/dev/null | sed 's/^/      /'

step "3/4  what got cabled"
docker exec bnk-worker ip link show eth1 >/dev/null 2>&1 || fail "bnk-worker has no eth1: the dc-edge cable was not created (see the deploy output above)"
ok "bnk-worker: $(docker exec bnk-worker ip -br link show eth1 | awk '{print $1, $2}') (no address: TMM will own this port)"
ok "client:     $(docker exec client ip -br addr show eth1 | awk '{print $1, $3}'), default via 10.20.20.254"
for _ in $(seq 1 20); do docker exec edge-router vtysh -c 'show ip route static' 2>/dev/null | grep -q 10.30.30.0 && break; sleep 1; done
docker exec edge-router vtysh -c 'show ip route' 2>/dev/null | grep -E '^(C|S)' | sed 's/^/      /'

step "4/4  prove the path up to BNK's door"
docker exec client ping -c1 -W2 10.20.20.254 >/dev/null && ok "client -> edge-router: reachable"
if docker exec edge-router ping -c1 -W2 10.10.10.11 >/dev/null 2>&1; then ok "edge-router -> TMM 10.10.10.11: reachable"
else ok "edge-router -> TMM 10.10.10.11: no answer yet, as expected: BNK is not installed"; fi
