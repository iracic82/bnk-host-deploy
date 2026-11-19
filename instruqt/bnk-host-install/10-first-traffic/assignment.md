---
slug: first-traffic
id: x28zyoh5bjug
type: challenge
title: First traffic through BIG-IP Next for Kubernetes
teaser: Ship an app the GitOps way, ask BNK for a VIP with the Gateway API, and send a request from a
  user behind the edge router, through TMM, to a pod. Then watch it spread across pods.
notes:
- type: text
  contents: |-
    ## Two teams, one API

    The Kubernetes **Gateway API** splits ingress into roles, which is how BNK is meant to be used:

    | Role | Owns | Here |
    |---|---|---|
    | **NetOps / platform** | `GatewayClass` (which load balancer), addresses, VLANs | `clusters/lab.network.yaml`, already applied by the install |
    | **App team** | `Gateway` (a listener on a VIP), `HTTPRoute` (which requests go to which Service) | what you write now |

    The app team never touches TMM, VLANs or routers. They ask for a listener in the
    `f5-gateway-class`, and BNK programs TMM to answer on a VIP.
tabs:
- id: dsxwfw9ggk0b
  title: VS Code
  type: service
  hostname: lab
  port: 8444
- id: enxfetob9fgt
  title: Terminal
  type: terminal
  hostname: lab
- title: Terminal 2
  type: terminal
  hostname: lab
- id: mhduhjfvvj8z
  title: Gitea
  type: service
  hostname: lab
  port: 3000
  custom_request_headers:
  - key: X-WEBAUTH-USER
    value: learner
- id: klhgogrcj0hv
  title: Lab Topology
  type: service
  hostname: lab
  port: 5050
- id: oocnkcdxeozi
  title: Argo CD
  type: service
  hostname: lab
  port: 8091
difficulty: intermediate
timelimit: 2400
enhanced_loading: null
---

# First traffic through BIG-IP Next for Kubernetes

---

## Step 1: Check the platform half is in place

```run
kubectl get gatewayclass f5-gateway-class
kubectl -n f5-bnk get f5-spk-vlans
kubectl -n f5-bnk get f5-bnkgateways -o jsonpath='{.items[0].spec.ingressConfig.defaultListenerNetworks}' | jq
```

- the GatewayClass is **Accepted**: BNK's controller (`f5.com/f5-bnk-f5-cne-controller`) owns it
- two VLANs, `external` (`10.10.10.11` on TMM interface 1.1) and `internal` (`172.18.0.250` on 1.2)
- a VIP pool `10.30.30.10` to `.29`

---

## Step 2: Read the app

Open `docs/examples/hello/hello.yaml` in **VS Code**. Five objects:

| Object | Purpose |
|---|---|
| `Namespace hello` | the app team's space |
| `Deployment hello` | **three** copies of `traefik/whoami`, a tiny web server that answers with its own pod name and the request it received |
| `Service hello` | one stable name for the three pods |
| `Gateway hello` | "give me an HTTP listener on port 80, at `10.30.30.10`, from `f5-gateway-class`" |
| `HTTPRoute hello` | "send everything on that listener to Service `hello`" |

> ### Concept: what BNK does with a Gateway
> BNK's controller sees the Gateway, takes the address from its pool, and configures TMM with a
> **virtual server** on `10.30.30.10:80`. The HTTPRoute becomes the virtual server's routing: its
> **pool members** are the **pod IPs** behind Service `hello` (not the Service's ClusterIP), so TMM
> load-balances straight to pods and follows them as they move. Reaching the pods, TMM uses its
> internal leg on the node network.

---

## Step 3: Ship it through git

Copy it into `apps/`, the directory delivered to the cluster:

```run
cd /root/workspace/bnk-host-deploy && git checkout -q main && git pull -q && git checkout -b hello-app
mkdir -p apps/hello && cp docs/examples/hello/hello.yaml apps/hello/hello.yaml
git add apps/hello && git commit -m "apps: hello, the first app behind BNK" && git push -u origin hello-app
```

Open the pull request in **Gitea** and **merge** it. What delivers it depends on your install path:

| Your path | What applies `apps/` | Where to watch |
|---|---|---|
| **A. CI/CD** | the `apps` workflow: a server-side dry run, then `kubectl apply` | Gitea > Actions |
| **C. Argo CD** | the `apps` Application (auto-sync, self-heal) within a minute | the Argo CD tab |
| **B. Forge** | Forge installs the platform; app teams ship their own way. Apply it as an app team would: | |

Forge path only:

```run
kubectl apply -f apps/hello/hello.yaml
```

Then watch the objects come up:

```run
kubectl -n hello get deploy,pod,gateway,httproute -o wide
```

The Gateway's `ADDRESS` shows `10.30.30.10` and `PROGRAMMED` turns `True`: TMM is now answering on
that VIP.

---

## Step 4: The first request

From the **client**, a user behind the edge router, not inside the cluster:

```run
lab curl http://10.30.30.10/
```

The answer comes from one of the `hello` pods: `Hostname: hello-…`, its pod IP, and the request
headers it saw.

Trace the path the request took:

```run
docker exec client traceroute -n -w 1 -q 1 -m 4 10.30.30.10
```

Two hops, and the second one **is the VIP**:

```
 1  10.20.20.254  0.004 ms     the edge router
 2  10.30.30.10   5.139 ms     TMM, answering as the VIP itself
```

TMM is not a router that forwards your packet onward; it **terminates** the connection on the
virtual server and opens a new one to a pod. So the trace ends at `10.30.30.10`. In challenge 2 this
same trace died after hop 1: the router had a route to `10.30.30.0/24`, but nobody owned the address.

| Hop | Who | Why it knows the way |
|---|---|---|
| client → `10.20.20.254` | edge router | the client's default route |
| router → `10.10.10.11` | TMM's external self IP (the next hop, not a hop of its own) | the router's route `10.30.30.0/24 via 10.10.10.11` |
| `10.30.30.10` | the virtual server on TMM | BNK programmed it from your Gateway |
| TMM → pod | a `hello` pod | the virtual server's pool, kept current by BNK's controller |

Now look back at the answer from the first request:

```
RemoteAddr: 172.18.0.250:33943
```

The pod did not see the client (`10.20.20.10`). It saw **`172.18.0.250`, TMM's internal self IP**:
TMM source-translates (SNAT automap) the second connection, so the pod's reply comes back to TMM
whatever the pod's routing says. That is the full-proxy model: two connections, TMM in the middle
of both, which is what lets it inspect, rewrite and secure the traffic.

---|---|---|
| client → `10.20.20.254` | edge router | the client's default route |
| router → `10.10.10.11` | TMM's external self IP | the router's route `10.30.30.0/24 via 10.10.10.11` |
| TMM → pod | a `hello` pod | the virtual server's pool, kept current by BNK's controller |

---

## Step 5: Load balancing across pods

Send twelve requests and count which pod answered each:

```run
for i in $(seq 1 12); do lab curl http://10.30.30.10/ | grep Hostname; done | sort | uniq -c
```

All three pods appear. Now delete one pod and send again straight away:

```run
kubectl -n hello delete pod "$(kubectl -n hello get pod -o jsonpath='{.items[0].metadata.name}')" --wait=false
for i in $(seq 1 12); do lab curl -o /dev/null -w '%{http_code} ' http://10.30.30.10/; done; echo
```

Every request still answers `200`: TMM's pool drops the dying pod and adds the replacement as
Kubernetes reports them.

The **Lab Topology** tab now lists `hello/hello @ 10.30.30.10 (programmed)` under Gateways.

Press **Check**: it sends a request from the client and expects a `hello` pod to answer.
