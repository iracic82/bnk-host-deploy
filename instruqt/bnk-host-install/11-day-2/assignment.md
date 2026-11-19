---
slug: day-2
id: qgmadlxp5z0a
type: challenge
title: 'Day 2: audit with Forge, change through git'
teaser: Install is day one. Point BNK Forge at the running cluster to audit what is
  deployed, prove the cluster still matches git, and make a change the only way changes
  should happen.
notes:
- type: text
  contents: |-
    ## Day 1 is the easy day

    Installing happens once. Then, for years: Which BNK release is running where? Did someone change
    something by hand? Is the licence still valid? Who installed this, from which commit? How do we
    upgrade twenty clusters safely?

    The repository answers *what should be*. **BNK Forge** answers *what is*: it reads the running
    cluster's BNK objects and shows versions, health, gateways, the licence, and keeps snapshots and
    drift history. It does that for any cluster you give it a kubeconfig for, however BNK got there.
    The two together are how a platform team runs BNK at scale.
tabs:
- id: eelx1ankvvbp
  title: BNK Forge
  type: service
  hostname: lab
  port: 8090
- id: v0pfovzjqazy
  title: Terminal
  type: terminal
  hostname: lab
- id: 9iuzmyvx99q6
  title: VS Code
  type: service
  hostname: lab
  port: 8444
- id: svvkp6ekou6a
  title: Gitea
  type: service
  hostname: lab
  port: 3000
  custom_request_headers:
  - key: X-WEBAUTH-USER
    value: learner
- id: lnly30pcn19s
  title: Lab Topology
  type: service
  hostname: lab
  port: 5050
difficulty: intermediate
timelimit: 2700
enhanced_loading: null
---

# Day 2: audit with Forge, change through git

---

## Step 1: Point Forge at the running cluster

If you took **path B**, Forge is installed and registered the cluster itself; skip to step 2.

On paths A and C, install Forge now, as the operations tool, and register the cluster:

```run
lab forge
lab forge-register
```

`lab forge` also sets `BNK_INSTALLER=forge`. Put the owner back to the tool that installed your
cluster, so the next challenge's change goes through it:

```run
source /opt/lab/lib.sh && set_owner "$(kubectl -n f5-bnk get cneinstance f5-bnk-instance -o jsonpath='{.metadata.annotations.bnk-host-deploy\.io/orchestrator}')"
```

Sign in to the **BNK Forge** tab as `admin` (password in `/root/.lab/forge-password`).

---

## Step 2: Audit what is running

In **Operate > Kubernetes**, open the cluster `lab`. Work through it like an auditor:

| Question | Where in Forge | What you should find |
|---|---|---|
| Which BNK release? | the cluster's BNK view | CNEInstance manifest **2.4.2**, FLO **v2.30.0-0.11.4** |
| Is it healthy? | **Operate > Health** / the cluster's health | the BNK components ready, TMM up on `bnk-worker` |
| Is it licensed? | licensing | state **Active** |
| What is exposed? | gateways / topology | Gateway `hello/hello` on `10.30.30.10` |
| What did it look like today? | **Operate > Snapshots**: take a snapshot | a point-in-time copy of the BNK configuration to diff against later |

Compare the release Forge shows with the one git pins, line for line:

```run
grep -E '^(BNK_VERSION|CNE_RELEASE_MANIFEST|FLO_VERSION)=' /root/workspace/bnk-host-deploy/versions.env
kubectl -n f5-bnk get cneinstance f5-bnk-instance -o jsonpath='{.spec.manifestVersion}{"\n"}'
helm -n f5-cne-core list -o json | jq -r '.[] | "\(.name) \(.chart)"'
```

---

## Step 3: Who installed it, from what

Every install stamped its provenance on the CNEInstance and appended it to a ledger in the cluster:

```run
kubectl -n f5-cne-core get configmap bnk-deploy-ledger -o json | jq -r '.data | to_entries[] | .value | fromjson | "\(.at)  by \(.by) (\(.actor))  release \(.release)  commit \(.commit[0:12])  \(.run)"'
```

Each line: when, which orchestrator, which commit, and (for the pipeline) a link to the run that did
it. An auditor's question, answered from the cluster itself.

---

## Step 4: Does the cluster still match git?

A plan against `main` should find nothing to do:

```run
lab plan 2>&1 | tail -25
```

**No changes**: the live CNEInstance and TMM network equal what `main` renders. On the CI/CD path the
`drift` workflow runs this every morning and opens an issue when a cluster stops matching.

---

## Step 5: A Day-2 change, through git

The hello app needs more capacity: five replicas instead of three. A change, so: a pull request.

```run
cd /root/workspace/bnk-host-deploy && git checkout -q main && git pull -q && git checkout -b hello-five
sed -i 's/replicas: 3/replicas: 5/' apps/hello/hello.yaml && git diff
git commit -am "apps/hello: 5 replicas" && git push -u origin hello-five
```

Merge it in **Gitea**. It lands through your path's delivery (the `apps` workflow, Argo CD's `apps`
Application, or on the Forge path `kubectl apply -f apps/hello/hello.yaml`). Then see TMM pick up the
new pods by itself:

```run
kubectl -n hello rollout status deploy/hello && for i in $(seq 1 20); do lab curl http://10.30.30.10/ | grep Hostname; done | sort | uniq -c
```

Five pod names. Nobody touched TMM, the router or BNK: the app team merged a change, and BNK's
controller updated the virtual server's pool.

> ### What an upgrade looks like here
> Upgrading BNK is the same motion. A pull request changes `versions.env` (`BNK_VERSION`,
> `CNE_RELEASE_MANIFEST`, `FLO_VERSION`, read from the new release manifest). `ci/targets.sh`
> selects **every enabled cluster**, the plan shows each one's diff (`manifestVersion: 2.4.2 → next`,
> the FLO chart version) on the pull request, and the merge rolls it out, one cluster after another.
> Forge's **Upgrade** view then confirms each cluster's new release and health.

---

## What you did today

| F5 guide step | Who did it for you |
|---|---|
| Prepare your computer and cluster | `00-preflight`, `05-nodes`, `10-prereqs` |
| Download FAR key and licence | the lab vault → CI secrets / Forge secrets / an Argo CD Secret |
| Create a pull-secret manifest for FAR | `20-registry` |
| Install FLO | `30-flo` |
| Install a CNE instance | `40-certs`, `45-attachments`, `50-cneinstance`, `55-network` |
| License your cluster | `60-license`, `65-ready` |
| (verify) | `70-verify`, provenance, nightly drift |

You did not run one of those steps by hand. You declared a cluster in git, chose a tool to apply
it, sent traffic through it, audited it, and changed it through review. That is how BNK is run at
scale.

Press **Check**: it confirms five hello pods answer through BNK.
