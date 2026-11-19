---
slug: the-repository
id: 3kclkdrnivaa
type: challenge
title: 'The repository: F5''s install guide, as code'
teaser: Read the installer the way you would review it at work. Map every phase to
  the page of F5's guide it replaces, run its tests, and register the CI runner that
  will execute it.
notes:
- type: text
  contents: |-
    ## One repository, every answer

    A platform team's install repository has to answer four questions without anyone asking a
    person:

    1. **What** gets installed? Exact versions, not "latest".
    2. **Where?** Which cluster, which node, which network.
    3. **How strictly?** A lab tolerates warnings; production does not.
    4. **Who ran it, when, and what changed?** Git history and pipeline runs.

    `bnk-host-deploy` keeps each answer in its own file, so a pull request that changes one thing
    changes one file. In this challenge you read it, test it, and give it a CI runner.
tabs:
- id: p0y7uwx4aedx
  title: VS Code
  type: service
  hostname: lab
  port: 8444
- id: clmpwfkyhsqz
  title: Terminal
  type: terminal
  hostname: lab
- id: 3xefvn3o8xif
  title: Gitea
  type: service
  hostname: lab
  port: 3000
  custom_request_headers:
  - key: X-WEBAUTH-USER
    value: learner
- id: bychkgcihvxi
  title: Lab Topology
  type: service
  hostname: lab
  port: 5050
difficulty: intermediate
timelimit: 2400
enhanced_loading: null
---

# The repository: F5's install guide, as code

---

## Step 1: Find the repository in Gitea, and your copy in VS Code

Open the **Gitea** tab. You are signed in as `learner`. Open **platform / bnk-host-deploy**.

> ### Concept: git, remotes and your working copy
> **git** records every change to a set of files as a *commit*, with an author, a time and a
> message. The copy in Gitea is the **remote**, the shared truth. The copy open in VS Code
> (`/root/workspace/bnk-host-deploy`) is your **working copy**, a clone of it. You change files
> locally, commit, and *push* a **branch** to the remote. Nothing you do locally affects anyone until
> you push, and nothing reaches `main` without a **pull request**: `main` is protected here, exactly
> as it would be at work. Try it later: a direct `git push origin main` is refused.

Now open the **VS Code** tab. The Explorer on the left shows the same repository.

---

## Step 2: The four layers of configuration

Open these files in VS Code, in this order. Each answers one question.

| File | Question | Look for |
|---|---|---|
| `versions.env` | **What** is installed | `BNK_VERSION=2.4.2`, `FLO_VERSION`, `CNE_RELEASE_MANIFEST`, and the comments explaining *why* each pin is what it is |
| `environments/lab.env` | **How strictly** | `BNK_STRICT_PREFLIGHT=false`, `BNK_WAIT_TIMEOUT`. Compare with `production.env` |
| `clusters/lab.yaml` | **Where** | the context, the storage class, `tmm.nodes: []` (empty!) and `enabled: false` |
| `profiles/host.yaml` | the **shape** of BNK | the CNEInstance template. Host mode: `dpu.enabled: false` |

> ### Concept: why layers
> If versions, policy and placement lived in one file, upgrading BNK on twenty clusters would be
> twenty edits, and any one of them could also change a timeout by accident. With layers, an
> upgrade is **one line in `versions.env`**, and the pipeline works out which clusters it affects.
> Adding a cluster is one new file in `clusters/`. A reviewer sees exactly what kind of change a
> pull request is from the files it touches.

Notice `clusters/lab.yaml` says `enabled: false` with an empty TMM node. **Nothing will be installed
until someone declares it**, in a reviewed pull request. That is your job in a later challenge.

---

## Step 3: Every phase is a page of F5's guide

The installer is `install.sh` plus one file per phase in `lib/`. Ask it what it would do:

```run
cd /root/workspace/bnk-host-deploy && ./install.sh --list-phases | cut -c1-80
```

| Phase | F5 guide step it automates | What would go wrong by hand |
|---|---|---|
| `00-preflight` | System requirements | You discover a missing tool or too few CPUs 25 minutes into the install |
| `05-nodes` | **Label TMM nodes** (`app=f5-tmm`) | Forget it and the operator never creates TMM, and its error never mentions labels |
| `10-prereqs` | **Install cert-manager** (+ Multus, the CA issuer) | Apply the issuer before cert-manager's webhook answers and it fails intermittently |
| `20-registry` | **Pull secret for F5 Artifact Registry** | Create it in one namespace instead of two and half the images never pull |
| `30-flo` | **Install FLO** (Helm, from `repo.f5.com`) | Install it before Multus and it crash-loops |
| `40-certs` | CWC/OTEL certificates (`f5-cert-gen`) | Without `make` and `python3`, cert-gen writes empty certificates and *reports success* |
| `45-attachments` | TMM's network legs (Multus NADs) | Must exist before the CNEInstance names them |
| `50-cneinstance` | **Install a CNE instance** | The object that makes FLO install ~80 components |
| `55-network` | TMM VLANs, VIP pool, GatewayClass | F5's validation webhook refuses everything until it is up |
| `60-license` | **License your cluster** | A race with a quota object fails one install in ten |
| `65-ready` | wait for TMM | Wait for "Available" *before* licensing and you wait forever |
| `70-verify` | the guide's "Expect:" lines | Turned into assertions that fail the run |

Open `lib/50-cneinstance.sh` and read the comment at the top: it explains why this phase does
**not** wait for the instance to become Available. Comments like that are hard-won knowledge; in a
repository they are kept, in a person's head they are lost.

---

## Step 4: Run the tests, like CI will

A pull request is only safe to merge if something checked it. These tests need no cluster:

```run
./tests/cluster.sh
```

It validates every cluster file, then feeds the validator **six broken files on purpose** and
confirms each one is rejected. (A validator nobody tested is a hope, not a check.)

```run
./tests/render.sh
```

It renders the CNEInstance exactly as phase 50 would, for the plain host profile and for the lab's
two-leg network, and checks the result.

---

## Step 5: The pipeline, in four files

Open `.github/workflows/` in VS Code:

| Workflow | When it runs | What it does |
|---|---|---|
| `ci.yml` | every pull request and push | lint, render, cluster-file tests (the tests you just ran) |
| `plan.yml` | pull requests that change *how or where* BNK is installed | runs the installer in **plan mode** against the real cluster: validates every object server-side, logs in to F5's registry, renders the CNEInstance, posts the result on the PR. **Changes nothing.** |
| `deploy.yml` | a merge to `main` | plan, then install, for exactly the clusters the merge affected |
| `apps.yml` | a merge that changes `apps/` | applies application manifests (challenge 10) |

> ### Concept: CI/CD, plan and apply
> **CI** (*continuous integration*) checks every change automatically before it is merged.
> **CD** (*continuous delivery*) puts merged changes into effect automatically. For infrastructure
> the safe pattern is **plan, review, apply**: the pipeline shows the exact effect of a change on
> the pull request, a person approves it by merging, and only then does the pipeline apply it, the
> same way Terraform's `plan`/`apply` works. Nobody runs an installer from a laptop, so every
> change has a reviewer, a log and a commit to roll back to.

These files are GitHub Actions workflows. Gitea Actions runs them unchanged: what you learn here is
what you would do on GitHub.

---

## Step 6: Give the pipeline a runner, beside the cluster

A workflow is only a description until a **runner** executes it. Look at the line all the
cluster-touching jobs share:

```yaml
runs-on: [self-hosted, bnk]
```

> ### Concept: hosted vs self-hosted runners
> GitHub's *hosted* runners live on the internet and cannot reach a private cluster's API server,
> and you would not want them holding its credentials. Infrastructure pipelines therefore use a
> **self-hosted runner** placed next to the cluster: it reaches the API privately, and the cluster's
> kubeconfig never leaves the building. The labels it registers with (`self-hosted`, `bnk`) are how a
> workflow picks it.

Register one:

```run
lab runner
```

It downloads the runner (and verifies its checksum), asks Gitea for a registration token scoped to
**this one repository**, registers with the labels `self-hosted`, `bnk` and `ubuntu-latest`, and
starts it as a service.

In **Gitea**, open the repository's **Settings > Actions > Runners**: `bnk-lab-runner` is listed,
idle, waiting for work. In **Lab Topology**, the Gitea box now says *runner: online beside the
cluster*.

Press **Check** when the runner is online.
