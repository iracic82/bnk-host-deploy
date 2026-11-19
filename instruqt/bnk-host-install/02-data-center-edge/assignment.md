---
slug: data-center-edge
id: 0q09dohbcb8y
type: challenge
title: Build the data-center edge BNK will serve
teaser: A router, a client and two networks. Learn why TMM needs its own network legs,
  what Multus and macvlan do, and how a VIP gets routed to a pod.
notes:
- type: text
  contents: |-
    ## A load balancer needs somewhere to stand

    BNK is not "inside" Kubernetes the way an app is. Its data plane, TMM, sits on the boundary:
    one foot in the data-center network where users and routers are, one foot in the cluster where
    the pods are. Before you install it, you build the boundary.

    In a real data center that boundary already exists: a top-of-rack switch, an edge router, a
    VLAN for your load balancers. Here you create a small copy of it with containers, so you can see
    every hop.
tabs:
- id: k1ghiw7e903w
  title: Terminal
  type: terminal
  hostname: lab
- id: wicyf4tjdkax
  title: Lab Topology
  type: service
  hostname: lab
  port: 5050
- id: dqpfs1b1xsxc
  title: VS Code
  type: service
  hostname: lab
  port: 8444
difficulty: basic
timelimit: 1500
enhanced_loading: null
---

# Build the data-center edge BNK will serve

By the end of this challenge you will have this, and you will know why every piece is there:

```
   client 10.20.20.10                                     the TMM node (bnk-worker)
        |                                                 eth1 (no address of its own)
   client-net 10.20.20.0/24                                     |
        |                                                       |
   edge-router (FRR) .254 ----- dc-edge 10.10.10.0/24 ----------+--> TMM 10.10.10.11 (after the install)
   "VIPs 10.30.30.0/24 live behind 10.10.10.11"
```

---

## Step 1: Understand the two kinds of networking in this lab

Kubernetes gives every pod **one** network interface, `eth0`, on the cluster's pod network (Calico,
from challenge 1). That is enough for apps. It is not enough for a load balancer that must also be
reachable from outside, on an address your routers know.

> ### Concept: Multus, the "second NIC" for pods
> **Multus** is a CNI plugin that calls other CNI plugins. With it, a pod gets its normal `eth0`
> from Calico *plus* extra interfaces described by **NetworkAttachmentDefinition** objects
> (*NADs*). BNK uses Multus to give TMM its data-plane legs. The F5 Lifecycle Operator won't even
> start without the Multus resource type present, which is why your installer puts Multus in first.

> ### Concept: macvlan, how a pod gets onto a physical network
> A **macvlan** interface is a child of a real NIC with its *own MAC address*. To the switch it
> looks like a separate machine plugged into the same port. When TMM gets a macvlan on the node's
> `eth1`, TMM appears on the `eth1` network as its own host, with its own self IP, and the node
> itself does not need an address there at all. One catch you will meet in the repository: a
> macvlan child cannot talk to its own parent. That is why the TMM node has a second extra NIC,
> `eth2`, for TMM's *internal* leg toward the nodes.

Look at the TMM node's interfaces now. `eth1` (into `dc-edge`) and `eth2` (into the cluster
network) were plugged in when the cluster was built; `eth1` deliberately has no IPv4 address:

```run
docker exec bnk-worker ip -br addr
```

---

## Step 2: Build the edge

One command builds the routers and networks. Read its output as it goes, every block explains
itself:

```run
lab network
```

What just happened:

1. **`client-net`** was created: the users' network, `10.20.20.0/24`.
2. **`edge-router`** started: **FRRouting** (FRR), the open-source routing suite that many
   commercial routers and SONiC build on. It has a leg in `dc-edge` (`.254`) and one in
   `client-net` (`.254`), and forwards between them.
3. **`client`** started: a container full of network tools (`curl`, `dig`, `tcpdump`) that plays a
   user. Its default route points at the edge router.
4. A path test: the client reaches the router; the router does **not** yet reach `10.10.10.11`,
   because nothing answers on TMM's address until BNK is installed.

Switch to **Lab Topology**: the *client* and *edge-router* boxes are now green.

---

## Step 3: Read the router's routing table

```run
docker exec edge-router vtysh -c 'show ip route'
```

Find these lines:

| Route | Meaning |
|---|---|
| `C>* 10.10.10.0/24 ... eth0` | **C**onnected: the router sits directly on `dc-edge` |
| `C>* 10.20.20.0/24 ... eth1` | Connected: it sits on `client-net` too |
| `S>* 10.30.30.0/24 [1/0] via 10.10.10.11` | **S**tatic: "the VIP range lives behind 10.10.10.11" |

> ### Concept: VIPs and why the router must know them
> A **VIP** (*virtual IP*) is an address that belongs to a service, not to a machine. When an app
> team asks BNK for a Gateway, BNK hands out a VIP from a pool (here `10.30.30.10` to `.29`) and
> TMM answers on it. Users reach a VIP only if the network routes the VIP range to TMM. Here a
> static route does that. Large sites use **BGP** instead: TMM *announces* its VIPs to the router
> (BNK's `dynamicRouting`), so the network learns them by itself and stops sending traffic to a TMM
> that is down. The FRR router you just started speaks BGP, so the same lab can grow into that.

---

## Step 4: Follow a packet that cannot arrive yet

Ask the client to reach the VIP your first app will use, and watch where it goes:

```run
docker exec client traceroute -n -w 1 -q 1 -m 3 10.30.30.10
```

Hop 1 is the edge router (`10.20.20.254`). Hop 2 never answers: the router sends the packet to
`10.10.10.11`, and nobody owns that address yet. After the install, that hop is TMM, and the
packet continues to a pod.

Now confirm the router really tries to reach TMM's address (an ARP request nobody answers):

```run
docker exec edge-router ip neigh show 10.10.10.11
```

`FAILED` or `INCOMPLETE` is the right answer today.

---

## Step 5: See where TMM's address and the VIPs are declared

These addresses were not invented by the network: they are written down in the repository, as the
desired state of this cluster. Open **VS Code** and look at:

- `clusters/lab.network.yaml`: TMM's VLANs (`external`, self IP `10.10.10.11` on interface `1.1`;
  `internal`, `172.18.0.250` on `1.2`), the VIP pool and the GatewayClass
- `clusters/lab.attachments.yaml`: the two NADs, `external-net` on `eth1` and `internal-net` on
  `eth2`

You will read them properly in the next challenge. For now notice: the network you just built and
the files in git agree. Keeping those two in agreement is what the rest of the lab automates.

---

## What you built, in F5's terms

| You built | F5 guide / BNK term |
|---|---|
| `dc-edge` and the node's `eth1` | the *external* network TMM's external VLAN lives on |
| the node's `eth2` | the *internal* leg TMM uses to reach nodes and pods |
| the static route on `edge-router` | how upstream routers reach the VIP pool (later: BGP) |

Press **Check**: it verifies the router, the client and the route to the VIP pool.
