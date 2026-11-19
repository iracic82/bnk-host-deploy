---
slug: mission
id: if1yav9gaw8w
type: challenge
title: 'Your mission: a bare cluster, and BNK by the end of the day'
teaser: Meet the cluster you will install BIG-IP Next for Kubernetes on, and the tools
  around it. Learn what BNK is made of and why platform teams never install it by
  hand twice.
notes:
- type: text
  contents: |-
    ## Welcome to Northwind Networks

    Northwind runs GPU clusters for its AI teams. Every new cluster needs **F5 BIG-IP Next for
    Kubernetes (BNK)** in front of it: it is the ingress, the egress, the firewall and, for AI
    workloads, the gateway to the models.

    Until now, one engineer installed BNK by following F5's guide line by line. It worked on the
    first cluster. On the fifth, two clusters ran different versions, one had a hand-edited
    certificate nobody could explain, and the engineer was on holiday when the sixth arrived.

    Today you fix that. You will take a **bare Kubernetes cluster** to a **licensed BNK 2.4.2
    serving real traffic** without running a single install command yourself, using the tools a
    platform team uses: git, pull requests, a pipeline, F5's BNK Forge, or Argo CD.
- type: text
  contents: |-
    ## What you have, and what you build

    **Already here (the "company" provides it):**
    - a three-node Kubernetes cluster, with nothing F5 on it
    - **Gitea**, your company's git server (think GitHub), with the `bnk-host-deploy` repository
    - **VS Code** in the browser, opened on your clone of that repository
    - a **Lab Topology** page that turns green as you build

    **You build:**
    1. the data-center edge BNK will serve: a router and a client
    2. a CI runner beside the cluster, and the installer's container image
    3. BNK itself, with **one** of three tools: a CI/CD pipeline, BNK Forge, or Argo CD
    4. a first application behind BNK, tested from the client
    5. a Day-2 change, through git
- type: text
  contents: |-
    ## How this lab works

    - Code blocks marked **run** can be clicked to run in the Terminal tab.
    - Every step says *what* you do and *why*, and which page of F5's install guide it replaces.
    - Three challenges in the middle are alternatives: you do **one** install path and press
      **Skip** on the other two. CI/CD is the recommended path.
    - Nothing in this sandbox is shared with anyone. Break it freely.
tabs:
- id: 5c5yhqtmzdor
  title: Terminal
  type: terminal
  hostname: lab
- id: wg8mkp63bygn
  title: Lab Topology
  type: service
  hostname: lab
  port: 5050
- id: 2npaiyuixvq1
  title: VS Code
  type: service
  hostname: lab
  port: 8444
- id: z1j09madjlto
  title: Gitea
  type: service
  hostname: lab
  port: 3000
  custom_request_headers:
  - key: X-WEBAUTH-USER
    value: learner
difficulty: basic
timelimit: 1200
enhanced_loading: null
---

# Your mission: a bare cluster, and BNK by the end of the day

In this first challenge you look around. You will see the cluster, understand what BIG-IP Next for
Kubernetes adds to it, and meet the tools you will use to install it. Nothing gets installed yet.

---

## Step 1: Look at the whole lab on one page

Open the **Lab Topology** tab.

It is a live drawing of your sandbox, refreshed every five seconds. Three zones:

| Zone | What it is |
|---|---|
| **Data center edge** | where users and the network live. Empty for now: you build it next challenge |
| **Kubernetes cluster "bnk"** | three nodes, Ready. Note the large *worker (TMM node)* box: that is where BNK's data plane will run |
| **Platform tooling** | Gitea is green. Forge, Argo CD and the registry are grey: you will build those |

Keep this tab in mind. Every time you finish something, come back and watch a box turn green.

---

## Step 2: Meet the cluster

Switch to the **Terminal** tab and ask Kubernetes which machines it has:

```run
kubectl get nodes -o wide
```

You should see three nodes, all `Ready`:

| Node | Role |
|---|---|
| `bnk-control-plane` | runs the Kubernetes API server, the scheduler, etcd. In this lab it also runs workloads |
| `bnk-worker` | will run **TMM**, BNK's data plane |
| `bnk-worker2` | a second worker for BNK's control-plane pods and your apps |

> ### Concept: Kubernetes in one paragraph
> Kubernetes runs containers across a group of machines (**nodes**) and keeps them running. You
> do not tell it *how* to start things; you tell it *what you want* (three copies of this web
> server, reachable on port 80) by sending **objects** to its **API server**. Controllers inside
> the cluster then work until reality matches what you asked for. `kubectl` is the command-line
> client for that API. Everything you install today, BNK included, is just more objects and more
> controllers.

> ### Concept: why the nodes are containers ("kind")
> A real cluster's nodes are servers or VMs. To fit a whole data center into one lab VM, this
> cluster uses **kind** (*Kubernetes in Docker*): each node is a Docker container running its own
> kubelet and container runtime. Kubernetes cannot tell the difference, and neither can BNK. One
> consequence matters later: all three nodes share this VM's Linux kernel.

See the node containers for yourself:

```run
docker ps --filter name=bnk- --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
```

---

## Step 3: How pods talk: the CNI

Pods need IP addresses, and routes so a pod on one node can reach a pod on another. Kubernetes
does not do that itself: it calls a **CNI plugin**.

> ### Concept: CNI, the Container Network Interface
> When the kubelet starts a pod, it asks the container runtime to create the pod's network
> namespace, then runs a **CNI plugin**: a small program from `/opt/cni/bin`, chosen by the config
> file in `/etc/cni/net.d/`. The plugin creates the pod's `eth0`, gives it an IP address and sets up
> routes. Which plugin you run decides how pod networking works across the cluster: overlay or
> routed, network policy or not.

This lab's setup installed three things. Check each one yourself.

**1. Calico, the cluster's CNI.** kind normally installs its own simple CNI (*kindnet*); this
cluster was built with it disabled and **Calico** installed instead, through the **Tigera operator**
(the operator that installs and upgrades Calico):

```run
kubectl get pods -n tigera-operator
kubectl get pods -n calico-system -o wide
```

One `calico-node` pod runs on every node (a DaemonSet): it programs the routes and policies on that
node. `calico-kube-controllers` watches the cluster, and `calico-typha` fans changes out to the
nodes.

**2. How Calico was configured.** The operator reads one object, the `Installation`:

```run
kubectl get installation default -o jsonpath='{.spec.calicoNetwork}' | jq
kubectl get ippools -o wide
```

| Setting | Value | Meaning |
|---|---|---|
| `cidr` | `192.168.0.0/16` | every pod gets an address from here |
| `encapsulation` | `VXLANCrossSubnet` | pod traffic between nodes on the same subnet is routed directly; across subnets it is wrapped in VXLAN |
| `natOutgoing` | `Enabled` | pods reaching outside the cluster leave with the node's address |
| `nodeAddressAutodetectionV4` | `interface: eth0` | Calico uses the nodes' `eth0` only. `eth1` and `eth2` on the TMM node are reserved for TMM |

**3. The CNI plugin binaries on each node.** kind ships only four plugins. Setup added the standard
set, because TMM's legs will need `macvlan`:

```run
docker exec bnk-worker ls /opt/cni/bin
docker exec bnk-worker sh -c 'ls /etc/cni/net.d/ && cat /etc/cni/net.d/10-calico.conflist | head -20'
```

`10-calico.conflist` is the file the kubelet reads: it says "for every pod, run `calico`, then
`bandwidth` and `portmap`".

**See it work.** Start a throwaway pod on each worker and ping one from the other across nodes:

```run
kubectl run cni-a --image=nicolaka/netshoot:v0.14 --overrides='{"spec":{"nodeName":"bnk-worker"}}' -- sleep 300
kubectl run cni-b --image=nicolaka/netshoot:v0.14 --overrides='{"spec":{"nodeName":"bnk-worker2"}}' -- sleep 300
kubectl wait --for=condition=Ready pod/cni-a pod/cni-b --timeout=120s
kubectl get pod cni-a cni-b -o wide
kubectl exec cni-a -- ping -c2 "$(kubectl get pod cni-b -o jsonpath='{.status.podIP}')"
kubectl delete pod cni-a cni-b --now
```

Two `192.168.x.y` addresses on two nodes, and the ping crosses between them through Calico.

> ### Concept: why Calico, specifically
> BNK's installer, the **F5 Lifecycle Operator**, checks which CNI the cluster runs and refuses to
> install on one it cannot classify. Calico is the CNI F5 tests BNK in host mode with (on OpenShift
> it is OVN-Kubernetes). BNK also adds a **pseudo-CNI** of its own on top: it steers pod traffic
> that leaves the cluster through TMM, which is how BNK does per-tenant egress and SNAT. Pick your
> CNI with BNK in mind, not after.

> ### What is not here yet: Multus
> A pod gets exactly one interface from Calico. TMM needs more: one toward the data-center network,
> one toward the nodes. That is the job of **Multus**, a "meta" CNI that adds extra interfaces to
> chosen pods. It is a BNK prerequisite, so the **installer** puts it in (phase 10), and you will
> watch it arrive. Confirm it is absent today:
>
> ```run
> kubectl get crd network-attachment-definitions.k8s.cni.cncf.io 2>&1 | tail -1
> ```

---

## Step 4: Hugepages, the one thing BNK needs from the kernel

```run
kubectl get nodes -o custom-columns='NODE:.metadata.name,CPU:.status.allocatable.cpu,MEMORY:.status.allocatable.memory,HUGEPAGES-2Mi:.status.allocatable.hugepages-2Mi'
```

Every node offers `4Gi` of **2Mi hugepages**.

> ### Concept: hugepages and TMM
> Memory is normally handed out in 4 KiB pages. TMM, BNK's packet engine (the same Traffic
> Management Microkernel that runs in every BIG-IP), wants large, pinned 2 MiB pages so its packet
> buffers never get swapped and the CPU's address cache rarely misses. TMM *requests* 2 GiB of
> hugepages. A node without them can never run TMM, and the symptom is a pod stuck in `Pending`
> that never mentions hugepages. The lab reserved them on the VM's kernel already; on a real
> server you set `vm.nr_hugepages`, or a kernel boot parameter, and restart the kubelet.

---

## Step 5: What is missing (that is the point)

Ask the cluster for anything F5:

```run
kubectl get crd | grep -c -E 'f5|cert-manager|cni.cncf.io' || true
kubectl get ns
```

Zero F5 resource types and no F5 namespaces: a clean cluster, the way a new one arrives.

Now see the whole picture in one command, the lab's status screen:

```run
lab status
```

Most of it says *not installed*. By the end of the lab every line will be filled in.

---

## Step 6: What BIG-IP Next for Kubernetes is made of

Before you install it, know what you are installing. BNK on a host (called **Host mode**: TMM runs
as a normal pod on the node's CPU, no DPU) is three layers:

| Layer | Components | What they do |
|---|---|---|
| **Operator** | F5 Lifecycle Operator (**FLO**) | Installs and upgrades everything else. You give it one object, a **CNEInstance**, and it lays down ~80 components from F5's *release manifest* |
| **Control plane** | CNE controller, CWC (licensing), DSSM (state), observer, cert services | Watches Kubernetes objects (Gateways, routes, VLANs) and programs TMM |
| **Data plane** | **TMM** (one pod on the node you choose) | Moves the packets: VIPs, load balancing, SNAT, firewall, AI gateway |

The install is an ordered list, which F5's guide *Install BNK (Host) on a self-managed cluster
using FLO* walks through: prepare the cluster, label the TMM node, install cert-manager, create
registry pull secrets, install FLO, generate certificates, create a CNEInstance, license it.

> ### Concept: why not just run the guide's commands?
> F5's older hands-on labs did exactly that: a script per step, run by hand, in order. It teaches
> the steps, but it does not scale: every cluster becomes a snowflake, nothing records what was
> run, and an upgrade means doing it all again carefully. In this lab every step of the guide is
> **code in a repository**, and a tool runs it. You will read that code in challenge 3, and see each
> phase print the page of F5's guide it replaces.

---

## Step 7: The three tools you can install it with

| Path | How BNK gets installed | Who uses it |
|---|---|---|
| **CI/CD pipeline** (recommended) | You change a file in a pull request. A pipeline *plans* (shows what would change), a human reviews, the merge *applies* | Platform teams who already ship everything through git |
| **BNK Forge** | F5's deployment and lifecycle tool runs the same installer as a module, step by step, with a UI and Day-2 views | Teams who want a console, approvals and fleet views |
| **Argo CD** | GitOps: Argo watches git and makes the cluster match it, continuously | Teams already running GitOps for everything else |

All three run **the same installer** from the same repository. That is the lesson of the day: the
install logic lives in one versioned place, and the orchestrator is a choice.

When you are ready, press **Check** to continue. (It checks that you ran `lab status`.)
