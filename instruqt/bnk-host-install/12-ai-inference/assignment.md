---
slug: ai-inference
type: challenge
title: "Two days later: the AI team moves in"
teaser: Put three simulated GPUs behind BIG-IP Next for Kubernetes and let BNK's endpoint picker send each
  request to the GPU that already holds its prompt. Then measure what that is worth against round robin.
notes:
- type: text
  contents: |
    ## A new tenant with expensive hardware

    Two days after the audit, a message from **Mei**, who leads Northwind's new AI team:

    > *"We're putting our support assistant on cluster six. Twelve customers, each with their own long
    > system prompt, three GPUs. Our first test behind a plain load balancer was slow and our GPU bill
    > was not. Can BNK do better?"*

    Priya forwards it to you with one line: *"This is what BNK was built for. Show them."*

    There are no GPUs in this lab. Each "GPU" is **llm-d's vLLM simulator**, the tool the Kubernetes
    inference community uses to test exactly this kind of routing. It speaks the OpenAI API, publishes
    vLLM's metrics, and simulates the two things that cost time on a real GPU: reading a prompt and
    writing an answer. Its answer text is filler. Its timings and its cache behave like the real thing.
- type: text
  contents: |
    ## How a GPU answers a question

    Every LLM request has two phases:

    | Phase | What the GPU does | What it costs |
    |---|---|---|
    | **prefill** | reads the whole prompt and computes attention data for every token, the **KV cache** | grows with prompt length, and sets the *time to first token* |
    | **decode** | writes the answer one token at a time, reusing that KV cache | grows with answer length |

    Mei's customers each send a long system prompt, the same few hundred tokens every time, plus a
    short question. If the GPU that receives the request **already holds that prompt's KV cache**, it
    skips most of the prefill. If not, it computes it all again, and evicts somebody else's to make
    room, because GPU memory is small and expensive.

    So *which GPU gets the request* decides whether it costs 50 ms or 700 ms. A load balancer that only
    counts connections cannot know. **An endpoint picker can.**
tabs:
- title: AI Inference
  type: service
  hostname: lab
  port: 5060
- title: Terminal
  type: terminal
  hostname: lab
- title: Terminal 2
  type: terminal
  hostname: lab
- title: VS Code
  type: service
  hostname: lab
  port: 8444
- title: Gitea
  type: service
  hostname: lab
  port: 3000
  custom_request_headers:
  - key: X-WEBAUTH-USER
    value: learner
- title: Argo CD
  type: service
  hostname: lab
  port: 8091
- title: BNK Forge
  type: service
  hostname: lab
  port: 8090
- title: Lab Topology
  type: service
  hostname: lab
  port: 5050
difficulty: intermediate
timelimit: 3600
enhanced_loading: null
---

# Two days later: the AI team moves in

![AI inference: the request reaches TMM on VIP 10.30.30.11, BNK's endpoint picker names the GPU that already holds the customer's prompt, and the warm GPU skips the prefill](../assets/diag-inference.png)

---

## Step 1: The idea, in Kubernetes terms

The **Gateway API Inference Extension** adds two things to the Gateway API you used in challenge 10:

| Object | What it is |
|---|---|
| **InferencePool** | a set of model-server pods, like a Service, but meant to be routed to *one request at a time* by a picker |
| **endpoint picker** | a small service the gateway asks, for every request: *which pod should take this one?* It looks at the prompt and at each pod's live metrics (queue, KV-cache use) |

An HTTPRoute can point at an InferencePool instead of a Service. Then, for every request, TMM
pauses, asks the picker, and sends the request to the pod the picker names.

**BNK ships its own endpoint picker, F5EPP.** You declare one `F5EPP` object, and BNK's controller
runs the picker for you. For safety, the controller only does that in namespaces the platform team
has approved, in the CNEInstance's `eppNamespaces` list. That approval is a platform change, so it
goes through git like every other.

---

## Step 2: The platform change (platform team)

Approve the namespace `inference` for endpoint pickers. Start a branch:

```run
cd /root/workspace/bnk-host-deploy && git checkout -q main && git pull -q && git checkout -b enable-inference
```

Open `clusters/lab.yaml` in **VS Code** and add, at the end of the file:

```yaml
inference:
  epp_namespaces: [inference]
```

Save, then validate, commit and push:

```run
./tests/cluster.sh clusters/lab.yaml && git commit -qam "clusters/lab: let BNK run endpoint pickers in namespace inference" && git push -u origin enable-inference
```

Open the pull request in **Gitea**. What this change makes the installer do:

| Phase | Action |
|---|---|
| **47 inference** (new) | installs the Inference Extension CRDs (InferencePool), then creates namespace `inference` with F5's pull secret |
| **50 CNEInstance** | adds `eppNamespaces: [inference]`, so BNK's controller may run pickers there |

> ### Concept: why phase 47 must run first
> The moment the CNEInstance lists an EPP namespace, BNK's controller restarts and starts watching
> InferencePool objects. If that resource type does not exist yet, the controller exits, and TMM
> stops being configured. The installer encodes the order once: CRDs and namespace in phase 47,
> the CNEInstance change in phase 50. Nobody has to remember it at two in the morning.

Now deliver it the way your path delivers platform changes. Check your path:

```run
lab owner
```

| `lab owner` says | How the platform change lands |
|---|---|
| **pipeline** | the plan comment on the pull request lists the new phase 47 actions and the CNEInstance diff (`+ eppNamespaces`). **Merge**, and `deploy` applies it |
| **argocd** | **Merge**. In the **Argo CD** tab, `bnk-install` turns **OutOfSync** (the ConfigMap from `clusters/` changed). **Sync** it |
| **forge** | **Merge** for the record. Forge runs the installer image you built earlier, so set the change in Forge itself: project `bnk-lab` > **Variables** > `epp_namespaces` = `inference`, then **Deploy all** |

When it has landed, confirm:

```run
kubectl get crd inferencepools.inference.networking.k8s.io
kubectl -n f5-bnk get cneinstance f5-bnk-instance -o jsonpath='{.spec.eppNamespaces}{"\n"}'
kubectl get ns inference --show-labels
lab status
```

The CRD exists, the CNEInstance lists `["inference"]`, the namespace is there, and `lab status` still
shows BNK Available. The controller restarted cleanly.

---

## Step 3: The AI team's change (app team)

Read the app in **VS Code**: `docs/examples/inference/inference.yaml`.

| Object | Purpose |
|---|---|
| `Deployment model` | three simulated GPUs, spread across the nodes. Each KV cache holds about **four** customers' prompts |
| `InferencePool model-pool` | those three pods, as one pool the picker routes to |
| `F5EPP model-pool-epp` | BNK's endpoint picker for the pool. BNK's controller turns this one object into a running picker |
| `Gateway ai-picker` + `HTTPRoute chat` | VIP **10.30.30.11**: requests go to the InferencePool, so the picker decides |
| `Service model-rr` + `Gateway ai-roundrobin` + `HTTPRoute chat-rr` | VIP **10.30.30.12**: the same pods behind a plain Service, round robin, for comparison |

Ship it like the hello app:

```run
cd /root/workspace/bnk-host-deploy && git checkout -q main && git pull -q && git checkout -b inference-app
mkdir -p apps/inference && cp docs/examples/inference/inference.yaml apps/inference/
git add apps/inference && git commit -qm "apps: inference, three simulated GPUs behind BNK's endpoint picker" && git push -u origin inference-app
```

**Merge** it in **Gitea**, and let your path deliver it (`lab owner`, as in challenge 10). Only on the
Forge path, apply it yourself:

```run
kubectl apply -f apps/inference/inference.yaml
```

Watch it come up. The picker's own pod appears next to the three model servers, rendered by BNK:

```run
kubectl -n inference get pods,inferencepool,f5epp,gateway -o wide
```

Both Gateways get their addresses, `10.30.30.11` and `10.30.30.12`, and turn `PROGRAMMED True`.

---

## Step 4: Ask one question, twice

From the client behind Sam's router, ask as customer 7:

```run
lab ask 7 "How do I reach my service from outside the cluster?"
lab ask 7 "And how do I make it highly available?"
```

The first answer is **cold**: none of customer 7's prompt was in any GPU's KV cache, so the GPU
prefilled all of it (`0 of ~305` cached). The second is **warm**: the picker sent it to the same GPU,
which still held the prompt (`~300 of ~305` cached), and the latency drops from several hundred
milliseconds to tens.

Now the same question through round robin:

```run
lab ask --rr 7 "And how do I make it highly available?"
```

Round robin does not know who holds what. Run it a few times: some answers are warm, by luck, most
are not.

---

## Step 5: Twelve customers, three GPUs

Open the **AI Inference** tab. The top shows the three GPUs, read live from each model server's own
vLLM metrics: requests served, and **KV-cache hit rate**, the share of prompt tokens served from the
cache instead of computed.

Press **Send 48 requests** under *BNK endpoint picker*. 48 requests from the twelve customers, in a
fixed random order, go through VIP `.11`. Then press **Send the same 48 requests** under *Round robin*:
the identical sequence through `.12`.

Read the two panels side by side:

| | Look for |
|---|---|
| **warm KV-cache hits** | how many of the 48 found their prompt already cached. Expect roughly **35 to 42** with the picker, and around **20** with round robin |
| **average and p95 latency** | the picker's average should be well under round robin's, often half |
| **the strip** | one square per request, coloured by the GPU that answered. Filled is warm, hollow is cold |
| **the customer grid** | with the picker, each customer sits in **one** GPU column. With round robin, every customer is smeared across all three, and every GPU keeps evicting prompts it will need again |

The same in the terminal, if you prefer:

```run
lab gpus
```

> ### Concept: what the picker is actually doing
> For every request, TMM sends BNK's picker the request's details over a gRPC side channel
> (**ext_proc**). The picker scores every pod: does it recently hold this prompt's prefix, how long is
> its queue, how full is its KV cache. It names the winner, and TMM sends the request there. It is
> the same full proxy you met in challenge 10, with a far smarter way of choosing the pool member.
>
> Here the picker tracks prefixes itself, from the requests it routes. With real vLLM, the model
> servers also publish **KV-cache events**, so the picker knows exactly which blocks each GPU holds.

> ### Concept: why this matters on a real bill
> Prefill is the most compute-hungry part of inference. Every cold request recomputes work another
> GPU already did. Routing for cache hits turns that waste into capacity: the same three GPUs serve
> more customers, faster. Replay real production chat traces through a KV-cache simulator and the effect is large:
> prefix-aware routing with a quarter of the GPU memory per GPU still saves more prefill than round
> robin with all of it.

---

## Step 6: What you built this week

| Day | What changed | How |
|---|---|---|
| Monday | BNK installed on cluster six | a cluster file, one of three install tools |
| Monday | the first app behind a VIP | a pull request to `apps/` |
| Day 2 | audit, drift check, more capacity | Forge, the ledger, a pull request |
| Two days later | AI inference, with a GPU-aware picker | a platform pull request, then an app pull request |

Mei's reply arrives before lunch: *"Same three GPUs, half the latency. Can we move the other models
too?"*

Press **Check**. It confirms the inference CRDs, the approved namespace, the model servers, BNK's
picker, and an answer through VIP 10.30.30.11.
