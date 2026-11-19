---
slug: cicd-plan
type: challenge
title: "Path A, CI/CD (1/2): declare the cluster, read the plan"
teaser: Say in a pull request that this cluster should have BNK, on which node, and let the
  pipeline show you exactly what an install would do, before anything changes.
notes:
- type: text
  contents: |-
    ## Choose your install path

    The next five challenges are three alternative ways to install BNK. Do **one** and press
    **Skip** on the challenges of the other paths.

    | Path | Challenges | You will |
    |---|---|---|
    | **A. CI/CD** (recommended) | 5 and 6 | change a file in a pull request; a pipeline plans, you merge, the pipeline installs |
    | **B. BNK Forge** | 7 and 8 | load the installer into Forge as a module and deploy it from Forge's UI |
    | **C. Argo CD** | 9 | install Argo CD; it pulls the install from git and runs it in the cluster |

    All three run the installer you just pinned. Whichever you choose, challenge 10 sends traffic
    through it and challenge 11 audits it with Forge.

    **Taking path B or C?** Press **Skip** now.
tabs:
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
- title: Terminal
  type: terminal
  hostname: lab
- title: Lab Topology
  type: service
  hostname: lab
  port: 5050
difficulty: intermediate
timelimit: 2400
---

# Path A, CI/CD (1/2): declare the cluster, read the plan

In this path **you never run the installer**. You describe what you want in git; the pipeline
does the rest, and shows you its plan first.

---

## Step 1: Give the pipeline its credentials, and the cluster

The pipeline needs two secrets to install BNK:

| Secret | What it is | Used by |
|---|---|---|
| `FAR_PULL_B64` | the **F5 Artifact Registry** service-account key | Helm (to pull the FLO and cert-gen charts from `repo.f5.com`) and the nodes (the `far-pull-secret` every BNK image is pulled with) |
| `BNK_LICENSE_JWT` | the **licence** token | the `License` object BNK validates with F5 (connected mode) |

In this lab both live in a vault (a Secret in the `lab-vault` namespace, standing in for HashiCorp
Vault or a cloud secret manager). Copy them into the repository's Actions secrets:

```run
lab ci-secrets
```

The values go from the vault straight into Gitea through its API. They never appear on screen or
on disk, and Gitea will never show them again: secrets are **write-only**. In **Gitea >
bnk-host-deploy > Settings > Actions > Secrets** you see the two names, and no values.

The command also sets the repository variable **`BNK_INSTALLER=pipeline`**.

> ### Concept: one owner per cluster
> This repository works with three install tools. If two of them acted on the same merge they
> would race each other on the same cluster. So the repository declares an owner: `plan.yml` and
> `deploy.yml` only act when `BNK_INSTALLER` is `pipeline`. In a real estate this is a per-cluster
> decision, written down rather than remembered.

---

## Step 2: Declare the cluster

Create a branch for the change:

```run
cd /root/workspace/bnk-host-deploy && git checkout -q main && git pull -q && git checkout -b enable-lab-cluster
```

Open `clusters/lab.yaml` in **VS Code** and make two edits:

1. **Which node runs TMM.** Change `nodes: []` to

   ```yaml
     nodes: [bnk-worker]
   ```

   `bnk-worker` is the node with the two extra NICs you looked at in challenge 2.

2. **Switch it on.** Change `enabled: false` to `enabled: true`.

Save (`Ctrl+S`). Before you commit, let the same validator CI uses check your edit:

```run
./tests/cluster.sh clusters/lab.yaml
```

You should see `ok clusters/lab.yaml env=lab enabled=true tmm=bnk-worker`. Try a mistake on
purpose: put two nodes in the list, `[bnk-worker, bnk-worker2]`, run the test again and read the
error, then put it back. Mistakes caught here never reach a cluster.

> ### What else that file declares (read, do not change)
> - `tmm.networks: [external-net, internal-net]`: TMM's two legs, interfaces 1.1 and 1.2, defined
>   in `clusters/lab.attachments.yaml`
> - `legacy_network_model: true`: TMM networking from `F5SPKVlan` objects and VIPs from an
>   `F5BnkGateway` pool, as in `clusters/lab.network.yaml`
> - `pseudo_cni_exclude`: address ranges BNK's pseudo-CNI must never steer through TMM (the service
>   range, the node network, the VIP pool), so cluster-internal traffic is left alone

---

## Step 3: Commit, push, open the pull request

```run
git commit -am "clusters/lab: install BNK, TMM on bnk-worker" && git push -u origin enable-lab-cluster
```

In **Gitea**, create the pull request from `enable-lab-cluster` into `main`. Title it *Install BNK
on the lab cluster*.

Two workflows start: `ci` (the static checks) and **`plan`**, because this change touches
`clusters/`.

---

## Step 4: Watch the plan run

Open **Actions** and click the running `plan` job. Follow it:

1. **which clusters does this change affect?** `ci/targets.sh` compares your branch with `main`.
   You changed `clusters/lab.yaml`, so the answer is that cluster and no other. (Change
   `versions.env` instead and it would list every enabled cluster.)
2. **plan each cluster** runs `./install.sh --cluster clusters/lab.yaml --plan`. Read the output:
   every phase prints the page of F5's guide it automates, then what it *would* do:
   - preflight checks the API server, the CNI (Calico), CPU, storage
   - `plan: would label bnk-worker with app=f5-tmm`
   - `the FAR key logs in to repo.f5.com`: the plan proves the credential works **before** anyone
     approves an install with it
   - `plan: would helm install f5-lifecycle-operator v2.30.0-0.11.4`
   - the **rendered CNEInstance**, the exact object phase 50 will apply
3. **post the plan on the pull request**: the whole plan lands as a comment.

> ### Concept: a plan that touches the real cluster, and changes nothing
> Plan mode talks to the live API server: it dry-runs objects **server-side** (so admission webhooks
> and CRD schemas really check them), and logs in to F5's registry with the real key. It writes
> nothing. That is what makes reviewing a pull request meaningful: the reviewer sees what *this*
> change does to *this* cluster, not what it might do.

---

## Step 5: Review it like a colleague would

Go back to the pull request's **Conversation** tab and read the plan comment. As the reviewer,
answer three questions before approving:

1. Is it the right cluster, and only that cluster?
2. Is it the version you expect? (`manifestVersion: "2.4.2"` in the CNEInstance)
3. Does TMM land where you intended? (`would label bnk-worker`, and `networkAttachments:
   external-net, internal-net`)

**Do not merge yet.** Merging is the install. That is the next challenge.

Press **Check**: it confirms the pull request exists and its plan succeeded.
