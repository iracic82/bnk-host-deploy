---
slug: argocd
id: p5axqk0wfwew
type: challenge
title: 'Path C, Argo CD: GitOps installs BNK from inside the cluster'
teaser: Install Argo CD, declare the cluster in git, and press Sync. Argo renders the install from the
  repository and runs your pinned installer as a Job inside the cluster.
notes:
- type: text
  contents: |-
    ## Push or pull

    A CI pipeline **pushes**: something outside the cluster, holding credentials to it, applies
    changes when git changes. **GitOps pulls**: a controller *inside* the cluster watches git and
    makes the cluster match it, continuously. Nothing outside holds cluster credentials, and a hand
    edit to the cluster is noticed (and, if you want, undone).

    **Argo CD** is the most widely used GitOps controller. In this path it does two jobs:

    | Argo CD Application | Watches | Syncs |
    |---|---|---|
    | `bnk-install` | `argocd/bnk-install/` | **manually**: installing a data plane is a decision |
    | `apps` | `apps/` | **automatically**, with self-heal (challenge 10) |

    **On path A or B?** Press **Skip**.
tabs:
- id: 3b2yt7qcdy1h
  title: Terminal
  type: terminal
  hostname: lab
- title: Terminal 2
  type: terminal
  hostname: lab
- id: cnrxhtqwiipp
  title: Argo CD
  type: service
  hostname: lab
  port: 8091
- id: ylekx7nrifnj
  title: VS Code
  type: service
  hostname: lab
  port: 8444
- id: dfkkazlpxqod
  title: Gitea
  type: service
  hostname: lab
  port: 3000
  custom_request_headers:
  - key: X-WEBAUTH-USER
    value: learner
- id: imz1a4ojnfch
  title: Lab Topology
  type: service
  hostname: lab
  port: 5050
difficulty: advanced
timelimit: 4200
enhanced_loading: null
---

# Path C, Argo CD: GitOps installs BNK from inside the cluster

---

## Step 1: Read what Argo will apply

In **VS Code**, open `argocd/bnk-install/`:

| File | What it is |
|---|---|
| `kustomization.yaml` | the list Argo renders. Its `configMapGenerator` takes **`clusters/lab.yaml` and its two network files straight from the repository** into a ConfigMap |
| `namespace.yaml`, `rbac.yaml` | a namespace `bnk-installer` and a service account with the rights the installer needs |
| `job.yaml` | a Kubernetes **Job** running your digest-pinned image with `args: ["install"]`, the ConfigMap mounted as `/config`, and the credentials Secret mounted as `/work/secrets` |

The Job is an Argo **Sync hook** (`argocd.argoproj.io/hook: Sync`): every sync runs it once, to
completion, and shows its log.

> ### Concept: why a ConfigMap from git, and why it matters
> Kustomize gives a generated ConfigMap a **name with a content hash** (`bnk-cluster-7g5k…`). Change
> `clusters/lab.yaml` in git and the name changes, so the Job changes, so Argo sees the
> application OutOfSync. The cluster's desired state flows from the same file the pipeline path
> uses: one source of truth, whichever tool applies it.

---

## Step 2: Install Argo CD

```run
lab argocd
```

What it does, in order:

1. applies Argo CD's upstream install manifest (pinned version) into namespace `argocd`
2. tells Argo to serve plain HTTP behind the tab, and lets kustomize read `clusters/` from the
   repository root (`--load-restrictor LoadRestrictionsNone`)
3. creates `bnk-installer/bnk-install-credentials` from the lab vault: the FAR key and the licence,
   as a Kubernetes Secret, **never in git** (in production: External Secrets or Sealed Secrets)
4. creates the two Applications, pointed at your Gitea repository
5. exposes the UI on the **Argo CD** tab, and sets `BNK_INSTALLER=argocd` so the pipeline stands aside

Open the **Argo CD** tab and log in as `admin` with the password the step printed.

You will see `bnk-install` **OutOfSync** and `apps` **Synced** (empty). Click `bnk-install`: the tree
shows the namespace, the service account and the Job Argo *would* create.

---

## Step 3: Declare the cluster in git

The repository still says `enabled: false` with no TMM node. A Job started now would refuse to
install, correctly. Change it the way every change goes in:

```run
cd /root/workspace/bnk-host-deploy && git checkout -q main && git pull -q && git checkout -b enable-lab-cluster
```

In **VS Code**, edit `clusters/lab.yaml`:

```yaml
  nodes: [bnk-worker]
```

and `enabled: true`. Validate, commit, push:

```run
./tests/cluster.sh clusters/lab.yaml && git commit -am "clusters/lab: install BNK, TMM on bnk-worker" && git push -u origin enable-lab-cluster
```

In **Gitea**, open the pull request and **merge** it. (Notice `plan` and `deploy` do not run: the
repository says Argo CD owns this cluster.)

---

## Step 4: Sync, and watch the install from inside the cluster

Argo polls git every minute (or press **Refresh** on `bnk-install`). The ConfigMap name changes,
because the file changed, and **App Diff** shows exactly that.

Press **Sync**, then **Synchronize**.

Argo applies the namespace and RBAC (sync waves `-2`, `-1`), then starts the hook Job. Click the
`bnk-install` Job, then its pod, then **Logs**: the same installer output you would see in the
pipeline, phase by phase, each with its F5 guide page, streaming from a pod.

Or follow it from the terminal:

```run
kubectl -n bnk-installer logs -f job/bnk-install
```

A cold install takes **15 to 25 minutes**. When the Job completes, Argo marks the sync **Succeeded**.

> ### Concept: the installer inside the cluster
> No kubeconfig left the cluster. The Job uses its own service account, and the only credentials
> it holds are mounted from a Secret for the life of one pod. That is the GitOps security
> argument: the cluster reaches out to git, nothing reaches in.

---

## Step 5: Confirm, and see who installed it

```run
kubectl -n f5-bnk get cneinstance f5-bnk-instance -o json | jq '{available: (.status.conditions[] | select(.type=="Available") | .status), stamp: (.metadata.annotations | with_entries(select(.key | startswith("bnk-host-deploy.io"))))}'
docker exec edge-router ping -c2 10.10.10.11
```

`orchestrator: argocd`. And TMM answers the edge router on its external self IP.

Press **Check**: it confirms the install Job succeeded and BNK is Available.
