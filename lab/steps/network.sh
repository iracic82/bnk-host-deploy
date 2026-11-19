#!/usr/bin/env bash
# lab network: build the data-center side BNK will serve. Two networks and two containers:
#
#   client (10.20.20.10) --client-net-- edge-router (FRR) --dc-edge 10.10.10.0/24-- bnk-worker eth1
#                                        .254 on both                                   (TMM's external leg)
#
# In a real data center these are your top-of-rack/edge router and a user somewhere behind it. The
# router knows one thing about BNK: "the VIP range 10.30.30.0/24 is reached via 10.10.10.11", TMM's
# external self IP. That static route is what BGP replaces later.
source "$(dirname "$0")/../lib.sh"
D=/root/.lab/frr; mkdir -p "$D"

step "1/4  client-net: the users' network"
docker network inspect client-net >/dev/null 2>&1 || docker network create client-net --subnet 10.20.20.0/24 --gateway 10.20.20.1 >/dev/null
docker network inspect dc-edge >/dev/null 2>&1 || fail "dc-edge is missing (setup creates it with the cluster)"
ok "client-net 10.20.20.0/24, dc-edge 10.10.10.0/24 (bnk-worker's eth1 is already plugged in here)"

step "2/4  edge-router: FRRouting, the open-source router suite many vendors build on"
cat > "$D/daemons" <<'CFG'
zebra=yes
bgpd=yes
staticd=yes
ospfd=no
ospf6d=no
ripd=no
ripngd=no
isisd=no
pimd=no
ldpd=no
nhrpd=no
eigrpd=no
babeld=no
sharpd=no
pbrd=no
bfdd=no
fabricd=no
vrrpd=no
vtysh_enable=yes
zebra_options="  -A 127.0.0.1 -s 90000000"
bgpd_options="   -A 127.0.0.1"
staticd_options="-A 127.0.0.1"
CFG
cat > "$D/frr.conf" <<'CFG'
frr defaults traditional
hostname edge-router
log stdout informational
ip forwarding
!
! The VIP pool lives behind TMM's external self IP.
ip route 10.30.30.0/24 10.10.10.11
!
line vty
CFG
if ! docker ps --format '{{.Names}}' | grep -qx edge-router; then
  docker rm -f edge-router >/dev/null 2>&1 || true
  docker run -d --name edge-router --hostname edge-router --restart unless-stopped --privileged \
    --network dc-edge --ip 10.10.10.254 -v "$D/daemons:/etc/frr/daemons" -v "$D/frr.conf:/etc/frr/frr.conf" \
    "$FRR_IMAGE" >/dev/null
  docker network connect --ip 10.20.20.254 client-net edge-router
fi
for _ in $(seq 1 20); do docker exec edge-router vtysh -c 'show ip route static' 2>/dev/null | grep -q 10.30.30.0 && break; sleep 1; done
docker exec edge-router vtysh -c 'show ip route' 2>/dev/null | grep -E '^(C|S)' | sed 's/^/      /'
ok "edge-router up: 10.10.10.254 (dc-edge), 10.20.20.254 (client-net)"

step "3/4  client: a box full of network tools (netshoot) that plays a user"
if ! docker ps --format '{{.Names}}' | grep -qx client; then
  docker rm -f client >/dev/null 2>&1 || true
  docker run -d --name client --hostname client --restart unless-stopped --cap-add NET_ADMIN \
    --network client-net --ip 10.20.20.10 "$CLIENT_IMAGE" sleep infinity >/dev/null
fi
docker exec client ip route replace default via 10.20.20.254
ok "client 10.20.20.10, default route via edge-router"

step "4/4  prove the path up to BNK's door"
docker exec client ping -c1 -W2 10.20.20.254 >/dev/null && ok "client -> edge-router: reachable"
if docker exec edge-router ping -c1 -W2 10.10.10.11 >/dev/null 2>&1; then ok "edge-router -> TMM 10.10.10.11: reachable"
else ok "edge-router -> TMM 10.10.10.11: no answer yet, as expected: BNK is not installed"; fi
