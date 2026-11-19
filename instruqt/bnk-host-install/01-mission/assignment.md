---
slug: mission
id: if1yav9gaw8w
type: challenge
title: 'Monday, 09:00: a new cluster, and nothing on it'
teaser: Join Northwind's platform team on the morning cluster six arrives. Meet the cluster, learn how
  its pods talk, and find out what BIG-IP Next for Kubernetes will add to it.
notes:
- type: text
  contents: |
    ## Northwind Networks, platform team

    It is your first Monday on Northwind's platform team, and the sixth GPU cluster arrived overnight.

    Northwind's AI teams live on these clusters. Lena's team runs **Atlas**, the search assistant the
    whole company asks questions of, and Atlas is waiting for this cluster. Before Atlas can move in,
    every cluster gets **F5 BIG-IP Next for Kubernetes (BNK)** in front of it: the way in, the way
    out, the firewall and the gateway to the models.

    Priya, who leads the team, puts a coffee next to your keyboard.

    *"Here is the honest history. Clusters one to five, we installed BNK by hand from F5's guide. It
    worked. Then two of them drifted to different versions, one has a certificate nobody can explain,
    and the person who did them is on holiday. Cluster six is going to be different. By the end of
    today I want BNK on it without anyone typing an install command, and I want us able to do it again
    on cluster seven in ten minutes."*
- type: text
  contents: |
    ## What the team has given you

    - **The cluster**: three nodes, Kubernetes 1.35, no F5 software on it at all.
    - **Gitea**: Northwind's git server (think GitHub). It holds `bnk-host-deploy`, the repository
      with F5's install guide written as code.
    - **VS Code**, opened on your own copy of that repository.
    - **Lab Topology**: a live map of your environment that lights up as you build.

    The day ahead: build the network edge BNK will serve, give the team's pipeline a runner, choose
    **one** way to install BNK (a CI/CD pipeline, F5's BNK Forge, or Argo CD), put Atlas's first service
    behind it, and finish the way every platform team should: auditing what you built.
- type: text
  contents: |
    ## How this lab works

    - Code blocks marked **run** can be clicked; they run in the Terminal tab.
    - Each challenge starts with what is happening at Northwind, then walks you through the work step by
      step, explaining every technology the first time you meet it.
    - Challenges 5 to 9 are three alternative install paths. Do **one** and press **Skip** on the
      others. The CI/CD path is the one Priya recommends.
    - Your sandbox is yours alone. Break things; that is what it is for.
tabs:
- id: 5c5yhqtmzdor
  title: Terminal
  type: terminal
  hostname: lab
- title: Terminal 2
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

# Monday, 09:00: a new cluster, and nothing on it

Priya's first rule for any new cluster: *before you change it, know it.* So this morning you change
nothing. You walk around the cluster, learn how its pieces talk, and find out exactly what BNK will
add, so that every step this afternoon makes sense before you take it.

---

## Step 1: The map on the wall

Open the **Lab Topology** tab. The team keeps it on a screen in the corner of the room.

It has three zones. On the left, the **data-center edge**: where users and routers live. It is empty,
because building it is your next job. In the middle, the **Kubernetes cluster**: three nodes, green,
and one big box marked *worker (TMM node)*, which is where BNK's engine will run. On the right, the
**platform tooling**: Gitea is green, Forge and Argo CD are grey and waiting.

Every time you finish something today, come back here. Watching a box turn green is the quickest
proof that what you did worked.

---

## Step 2: Meet the cluster

Switch to the **Terminal** and ask the cluster what it is made of:

```run
kubectl get nodes -o wide
```

Three nodes answer, all `Ready`. `bnk-control-plane` runs the cluster's brain (the API server, the
scheduler, the etcd database) and, here, ordinary work too. `bnk-worker` is the one Priya has set
aside for BNK's data plane. `bnk-worker2` will carry everything else.

What is Kubernetes actually doing with these three machines? It is easiest to think of it as a
promise-keeper. You never tell Kubernetes *how* to start something. You tell it *what you want*,
"three copies of this web server, reachable on port 80", by sending an **object** to its **API
server**. Small programs inside the cluster, the **controllers**, then work tirelessly until
reality matches the promise, and keep it matching: kill one of the three copies and a controller
starts a fourth before you have finished reading the error. `kubectl`, the command you just ran, is
simply a client for that API. Everything you install today, BNK included, is more objects and more
controllers keeping more promises.

There is one surprise in this cluster. Ask Docker what is running on this machine:

```run
docker ps --filter name=bnk- --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
```

The three "machines" are **containers**. Northwind's real clusters run on racks of servers, but for
cluster six the team built a faithful copy with **kind**, *Kubernetes in Docker*, where every node
is a container running a real kubelet and a real container runtime. Kubernetes cannot tell the
difference, and neither can BNK. Remember one consequence: all three nodes share this VM's Linux
kernel. That will matter in step 4.

---

## Step 3: How the pods talk to each other

Every application in Kubernetes runs in a **pod**, and every pod gets its own IP address. That
raises a question Kubernetes deliberately refuses to answer itself: *who hands out those addresses,
and how does a packet from a pod on one node find a pod on another?*

The answer is a plug-in. When the kubelet starts a pod, it creates an empty network namespace for it
and then calls a **CNI plugin** (*Container Network Interface*): a small program from the node's
`/opt/cni/bin`, chosen by a config file in `/etc/cni/net.d/`. The plugin gives the pod its `eth0`,
an address, and the routes it needs. Which plugin you choose decides how your whole cluster's
network behaves.

Northwind chose **Calico**, and the reason is BNK. F5's installer checks which CNI a cluster runs
and refuses to install on one it cannot recognise, and Calico is the one F5 tests BNK in host mode
with. The lesson Priya wants you to take away: *pick your CNI with BNK in mind, not after.*

When the cluster was built, kind's own simple CNI was switched off and Calico installed instead,
through the **Tigera operator**, a controller whose only job is to install and look after Calico.
See both:

```run
kubectl get pods -n tigera-operator
kubectl get pods -n calico-system -o wide
```

A `calico-node` pod runs on every node (a **DaemonSet**, Kubernetes' way of saying "one on each"),
programming that node's routes. `calico-kube-controllers` watches the cluster as a whole.

The operator reads its instructions from a single object, the `Installation`. Read the network part
of it, and the pool of addresses Calico hands out:

```run
kubectl get installation default -o jsonpath='{.spec.calicoNetwork}' | jq
kubectl get ippools -o wide
```

Every pod's address comes from `192.168.0.0/16`. Between nodes on the same subnet Calico simply
routes; across subnets it would wrap packets in VXLAN (`VXLANCrossSubnet`). Pods talking to the
outside world leave with their node's address (`natOutgoing`). And look at the last setting:
Calico only uses each node's `eth0`. That is deliberate. `bnk-worker` has two more network cards,
and they are being kept for BNK.

Now look at the plug-ins themselves, on the node BNK will use. kind ships only four; the team added
the standard set, because BNK will need one called `macvlan` later today:

```run
docker exec bnk-worker ls /opt/cni/bin
docker exec bnk-worker sh -c 'ls /etc/cni/net.d/ && head -20 /etc/cni/net.d/10-calico.conflist'
```

`10-calico.conflist` is the instruction the kubelet follows for every new pod: a *chain* of plug-ins.
First `calico` (the interface, the address from `calico-ipam`, the network policy), then `portmap`
(so a pod's `hostPort` works). Notice the API address inside it, `https://10.96.0.1:443`: the
plug-in asks the Kubernetes API for every pod it wires up, which is why a node that cannot reach
that address cannot start a single pod.

Seeing is believing. Start one throwaway pod on each worker and make one ping the other, across
nodes, through Calico:

```run
kubectl run cni-a --image=nicolaka/netshoot:v0.14 --overrides='{"spec":{"nodeName":"bnk-worker"}}' -- sleep 300
kubectl run cni-b --image=nicolaka/netshoot:v0.14 --overrides='{"spec":{"nodeName":"bnk-worker2"}}' -- sleep 300
kubectl wait --for=condition=Ready pod/cni-a pod/cni-b --timeout=180s
kubectl get pod cni-a cni-b -o wide
kubectl exec cni-a -- ping -c2 "$(kubectl get pod cni-b -o jsonpath='{.status.podIP}')"
kubectl delete pod cni-a cni-b --now
```

Two `192.168.x.y` addresses, two different nodes, and replies coming back. That is the cluster's
pod network, working.

Look closely at one number in the replies: **`ttl=62`**. Every packet leaves with a *time to live*
of 64, and every router it passes through takes one off. 62 means the packet crossed exactly **two
routers**: the node `cni-a` lives on, and the node `cni-b` lives on, each routing for its own pods.
That is Calico at work: it does not stretch one big switch across the cluster, it makes every node a
small router and teaches each one where the other nodes' pods live. You can see those lessons on any
node: `docker exec bnk-worker ip route` shows a route to each other node's block of pod addresses.

There is one thing a pod network like this cannot do, and it is exactly what BNK needs. A pod gets
**one** interface from Calico. BNK's engine has to stand with one foot in the cluster and one foot in
the data center, and that needs extra network interfaces in a pod. The tool for that is **Multus**, a
"meta" plug-in that adds more interfaces to chosen pods. It is a BNK prerequisite, so it is not here
yet: BNK's installer will put it in, and you will watch it arrive. Confirm it is missing:

```run
kubectl get crd network-attachment-definitions.k8s.cni.cncf.io 2>&1 | tail -1
```

---

## Step 4: The one thing BNK needs from the kernel

```run
kubectl get nodes -o custom-columns='NODE:.metadata.name,CPU:.status.allocatable.cpu,MEMORY:.status.allocatable.memory,HUGEPAGES-2Mi:.status.allocatable.hugepages-2Mi'
```

Every node offers `4Gi` of **hugepages**. Here is why that column exists.

Normally Linux hands memory out in small 4 KiB pages, and the processor keeps a small cache of where
recently used pages live. BNK's engine, **TMM** (the *Traffic Management Microkernel*, the same
packet engine that runs inside every BIG-IP), moves millions of packets a second through big buffers.
With small pages it would constantly miss that cache. So TMM asks for **2 MiB pages**, pinned in
memory where they can never be swapped out, and it asks for 2 GiB of them.

If a node cannot offer hugepages, TMM simply never starts, and the only symptom is a pod waiting
forever in `Pending` without a word about hugepages. The team reserved them on this VM's kernel
before handing you the cluster (that is the "all nodes share one kernel" consequence from step 2: one
setting, three nodes). On real servers this is a kernel setting, `vm.nr_hugepages`, and a kubelet
restart.

---

## Step 5: What is missing (which is the point)

Ask the cluster for anything F5, and look at its namespaces:

```run
kubectl get crd | grep -c -E 'f5|cert-manager|cni.cncf.io' || true
kubectl get ns
```

Zero. A clean cluster, exactly how they arrive from the hardware team. Now the whole picture in one
screen, the team's status command:

```run
lab status
```

Most of it says *not installed*. By the end of the day every line will be filled in.

---

## Step 6: What you are about to install

Priya draws three boxes on the whiteboard.

*"BNK in **Host mode** means TMM runs as an ordinary pod on a node's CPU. No special hardware, no
DPU. It is three layers."*

The **operator** at the bottom: the **F5 Lifecycle Operator**, FLO. You never install BNK's eighty
components yourself. You give FLO one object, a **CNEInstance**, that says "BNK release 2.4.2, this
size, this network", and FLO installs everything listed in F5's *release manifest* for that release,
and upgrades it later.

The **control plane** in the middle: the controller that watches Kubernetes objects (Gateways,
routes, VLANs) and turns them into TMM configuration, plus licensing, state storage and certificate
services.

The **data plane** on top: **TMM**, one pod on the node you choose, actually moving the packets:
virtual servers, load balancing, address translation, the firewall.

F5's guide, *Install BNK (Host) on a self-managed cluster using FLO*, gets you there in a fixed
order: prepare the cluster, label the TMM node, install cert-manager, create the registry pull
secrets, install FLO, generate certificates, create the CNEInstance, license it.

*"Every one of those steps is in our repository as code,"* Priya says. *"You will read that code
this morning, and this afternoon a tool runs it. Which tool is up to you."*

---

## Step 7: Three ways to install, one installer

| | How BNK gets installed | Why a team picks it |
|---|---|---|
| **CI/CD pipeline** | You change a file in a pull request. A pipeline shows the plan, a colleague reviews it, the merge installs | Everything already goes through git and review |
| **BNK Forge** | F5's deployment and lifecycle tool runs the same installer step by step, with a console | You want a UI, step-level retries and fleet views |
| **Argo CD** | The cluster pulls its desired state from git and makes itself match | You run GitOps for everything else |

All three run the **same installer**, from the same repository, pinned to the same build. That is the
quiet lesson of the day: the knowledge of how to install BNK lives in one versioned place, and the
tool that runs it is a choice you can change.

Press **Check** when you have run `lab status`. Next, you build the edge of the data center.
