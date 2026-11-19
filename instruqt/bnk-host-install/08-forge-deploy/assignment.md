---
slug: forge-deploy
id: 8tiftu0mx7ps
type: challenge
title: 'Path B, BNK Forge (2/2): deploy from Forge, step by step'
teaser: Press Deploy and watch Forge run your pinned installer as ten visible steps,
  each with its own log, then find the cluster registered on Forge's Kubernetes page.
notes:
- type: text
  contents: |-
    ## What happens when you press Deploy

    Forge's engine reads the module's step list and, for each step, starts **one short-lived
    container** from your digest-pinned image, through its scoped Docker proxy, with:

    - the project's three secrets written to `/work/secrets/` (mode 0600)
    - a persistent workspace at `/work`, kept between steps and between runs
    - the form inputs as environment variables (`TMM_NODE=bnk-worker`)
    - CPU and memory limits, no Linux capabilities, a non-root user, a dedicated network

    The container runs `bnk-host <phase>`, its output streams into Forge, and the next step starts
    only if it succeeded. A cold install takes **15 to 25 minutes**.

    **On path A or C?** Press **Skip**.
tabs:
- id: hzxvzqaxkaa3
  title: BNK Forge
  type: service
  hostname: lab
  port: 8090
- id: 6a4d353cjcir
  title: Terminal
  type: terminal
  hostname: lab
- id: lqwxqtxtq9yz
  title: Lab Topology
  type: service
  hostname: lab
  port: 5050
difficulty: intermediate
timelimit: 3600
enhanced_loading: null
---

# Path B, BNK Forge (2/2): deploy from Forge, step by step

---

## Step 1: Deploy

In **BNK Forge**, open **Build > Projects > bnk-lab**. You see one module, *BNK 2.4.2 Host install*,
with the inputs you gave it and a *Secrets* section showing all three secrets present.

Press **Deploy** (deploy all).

(The same thing through the API, if you prefer: `lab forge-deploy bnk-lab bnk-worker`.)

---

## Step 2: Follow the steps

Open the module's **log / deployment** view. Each step appears as it starts:

| Forge step | What it does in the cluster | F5 guide |
|---|---|---|
| `00 preflight` | API reachable from the runner container, Calico, CPU, storage | System requirements |
| `05 label the TMM node` | `app=f5-tmm` on `bnk-worker`, hugepages proven | Label TMM nodes |
| `10 multus + cert-manager` | Multus, cert-manager, the CA issuer | Install cert-manager |
| `20 registry + pull secret` | Helm login to `repo.f5.com`, `far-pull-secret` ×2 | Pull secret for FAR |
| `30 lifecycle operator` | `helm install f5-lifecycle-operator` | Install FLO |
| `40 CWC + OTEL certs` | `f5-cert-gen`, certificates checked non-empty | Prepare the CNE core |
| `50 CNEInstance` | the operator lays down ~80 components | Install a CNE instance |
| `60 licence` | `License` object, validated with F5 | License your cluster |
| `65 wait for the data plane` | TMM created on `bnk-worker`, Available | |
| `70 verify` | every "Expect:" of the guide; provenance stamped | |

While it runs, watch the runner containers come and go on the VM. Each is one step:

```run
watch -n3 "docker ps --filter ancestor=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep bnk-host-deploy | head -1) --format 'table {{.Names}}\t{{.Command}}\t{{.Status}}'"
```

(`Ctrl+C` to stop.) And the cluster filling up:

```run
kubectl get pods -A --no-headers | grep -vE 'kube-system|calico|tigera|local-path' | awk '{print $1}' | sort | uniq -c
```

> ### Concept: why one container per step
> If step 50 fails, Forge shows *that* step's log, and **Retry** re-runs from there with the same
> workspace: the earlier steps are not repeated blindly. Every step runs the exact image digest
> the module pinned, so a retry next week runs the same code. Forge never needs kubectl, helm or
> the installer on its own servers.

---

## Step 3: The cluster, as Forge sees it

When the module shows **Applied**, open **Operate > Kubernetes**. The module's `cluster` block made
Forge register the cluster it just installed, with the kubeconfig from the project's secret. Open it:
nodes, namespaces, and BNK's own view (the CNEInstance, TMM, the licence).

The module's **outputs** (on the module card) are what `bnk-host verify` wrote: the release
manifest, `cneinstance_available: True`, `license_state: Active`, `tmm_node: bnk-worker`.

From the terminal, the same facts, plus who installed it:

```run
kubectl -n f5-bnk get cneinstance f5-bnk-instance -o json | jq '.metadata.annotations | with_entries(select(.key | startswith("bnk-host-deploy.io")))'
docker exec edge-router ping -c2 10.10.10.11
```

`orchestrator: forge`, the image's commit, the time: provenance lives on the object itself. And the
edge router now reaches TMM's external self IP.

Press **Check**: it confirms the Forge deployment applied and BNK is Available.
