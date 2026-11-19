---
slug: cicd-deploy
id: 8yekglxwxkpa
type: challenge
title: 'Path A, CI/CD (2/2): merge, and watch the pipeline install BNK'
teaser: The merge is the approval. Follow the install phase by phase in the pipeline
  log while the cluster fills up, and learn what every BNK component you see is for.
notes:
- type: text
  contents: |-
    ## Merging is deploying

    In the last challenge the pipeline showed you its plan on the pull request. Merging that pull
    request is your approval. The `deploy` workflow then runs on `main`: it plans once more (main may
    have moved since the review), then installs, for exactly the clusters the merge changed.

    A cold install pulls about 80 container images and takes **15 to 25 minutes**. This challenge
    uses that time to show you what each piece is, as it arrives.

    **On path B or C?** Press **Skip**.
tabs:
- id: 5uzpoeyw0ykb
  title: Gitea
  type: service
  hostname: lab
  port: 3000
  custom_request_headers:
  - key: X-WEBAUTH-USER
    value: learner
- id: iqyqd1yqmtvs
  title: Terminal
  type: terminal
  hostname: lab
- id: 6tflwyjnco7s
  title: Lab Topology
  type: service
  hostname: lab
  port: 5050
- id: yphentt15zhy
  title: VS Code
  type: service
  hostname: lab
  port: 8444
difficulty: intermediate
timelimit: 3600
enhanced_loading: null
---

# Path A, CI/CD (2/2): merge, and watch the pipeline install BNK

---

## Step 1: Merge

In **Gitea**, open your pull request *Install BNK on the lab cluster* and press **Merge**.

Open **Actions**: a `deploy` run has started on `main`. Click into it. (A `ci` run starts too: every
push to `main` is checked again.)

> ### Concept: what triggered it
> `deploy.yml` starts on a push to `main` that changes `clusters/**`, `environments/**`,
> `profiles/**`, `lib/**`, `versions.env` or `install.sh`. Its first step works out *which*
> clusters the merge affected (`ci/targets.sh` between the previous and the new commit) and acts on
> those only. A merge that only edits documentation wakes nothing. A merge that bumps `versions.env`
> would upgrade every enabled cluster, each one planned first.

---

## Step 2: Follow the phases, and see each one land in the cluster

Keep the deploy log open in one tab and run this in the **Terminal**: it shows the namespaces BNK
creates as they fill up (press `Ctrl+C` to stop it whenever you like):

```run
watch -n5 'kubectl get pods -A --no-headers | grep -vE "kube-system|calico|tigera|local-path" | awk "{print \$1}" | sort | uniq -c'
```

As each phase runs in the pipeline log, here is what it does and what to look for:

**`00 preflight`.** Checks tooling, the API server, Kubernetes 1.35, Calico, CPU and storage
*before* touching anything. Every check that fails here would otherwise fail 20 minutes later.

**`05 label the TMM node`.** `kubectl label node bnk-worker app=f5-tmm`, then proves the node offers
hugepages. The label is how the operator knows where TMM may run.

**`10 cluster prerequisites`.** Three things arrive:
- **Multus** (namespace `kube-system`, DaemonSet `kube-multus-ds`): gives pods extra NICs
- **cert-manager** (namespace `cert-manager`): issues and renews TLS certificates
- a **CA chain**: a self-signed root `f5-cne-internal-ca-root` and a `ClusterIssuer`
  `f5-cne-internal-ca` that signs every certificate BNK's components use to talk to each other

> ### Concept: why BNK needs its own certificate authority
> BNK's components talk to each other over mutual TLS (gRPC between the controller and TMM, the
> licensing service, telemetry). cert-manager issues those certificates from the CA this phase
> creates, and renews them before they expire, with no human involved.

**`20 registry`.** Logs Helm in to `repo.f5.com` and creates `far-pull-secret` in `f5-cne-core` and
`f5-bnk`. Every BNK image is private; without this secret every pod sits in `ImagePullBackOff`.

**`30 lifecycle operator`.** `helm install f5-lifecycle-operator` into `f5-cne-core`. Watch for the
`f5-lifecycle-operator` pod. The log then says how many F5 resource types (CRDs) it registered.

> ### Concept: operators
> An **operator** is a controller that knows how to run one piece of software. You give it a short
> description of what you want; it does the hundreds of steps. FLO's input is a **CNEInstance**,
> and its knowledge is F5's *release manifest*: the exact image and chart of every BNK component in
> release 2.4.2.

**`40 certificates`.** Runs F5's `f5-cert-gen` for the licensing service's certificates (CWC), and
checks they really contain certificates. (An earlier version of this installer once "succeeded"
with empty ones; the check exists because of that.)

**`45 attachments`.** Applies `clusters/lab.attachments.yaml`: `external-net` becomes TMM's
interface 1.1, `internal-net` 1.2.

**`50 CNEInstance`.** The big one. The log prints *reconciling* with a pod count that climbs. In your
watch you will see `f5-bnk` grow: the CNE controller, DSSM (BNK's state store, three replicas),
the observer, CSRC (a per-node agent), the cert service, and more.

**`55 network`.** Applies `clusters/lab.network.yaml` through F5's validation webhook, retrying while
it starts: VLANs `external` (`10.10.10.11`) and `internal` (`172.18.0.250`), the VIP pool and the
`f5-gateway-class` GatewayClass.

**`60 licence`.** Creates the `License` object. BNK validates it with F5 over the internet
(*connected mode*) and the state turns `Active`.

**`65 wait for the data plane`.** Only now, licensed, does the controller create **TMM**. Watch for
`f5-tmm` on `bnk-worker`. When it is up, the CNEInstance turns **Available**.

**`70 verify`.** The guide's "Expect:" lines as assertions: FLO running, CRDs present, no crash
loops, no image pull errors, licence Active, GatewayClass accepted, VLANs programmed.

---

## Step 3: See it from the outside

When `deploy` is green, look at the result three ways.

The **Lab Topology** tab: the TMM box and the BNK control plane are green, with version, licence
and GatewayClass filled in.

The cluster's own view:

```run
kubectl -n f5-bnk get cneinstance f5-bnk-instance -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'
kubectl -n f5-bnk get pods -l app=f5-tmm -o wide
kubectl get license.k8s.f5net.com -A
```

And the moment of truth from the router: TMM now answers on `10.10.10.11`:

```run
docker exec edge-router ping -c2 10.10.10.11
```

Two challenges ago, nothing owned that address. Now TMM does, through its macvlan on `bnk-worker`'s
`eth1`.

---

## Step 4: Prove it is repeatable

Re-run the deploy on purpose. In **Gitea > Actions**, select the `deploy` workflow and use **Run
workflow** (leave the cluster empty to target every enabled cluster). Every phase reports
*already present* or *already installed*, and the run is quick: the installer **converges**. It
brings the cluster to the declared state and does nothing if it is already there. That is what makes
it safe to run from a pipeline as often as you like.

Press **Check**: it confirms the deploy succeeded and BNK is Available.
