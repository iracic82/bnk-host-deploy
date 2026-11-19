---
slug: pin-the-runner
type: challenge
title: Build the installer image and land your first pull request
teaser: Package the installer as a container image, pin it by digest, and get the change into main
  the way every change will go in from now on, through a pull request and CI.
notes:
- type: text
  contents: |-
    ## One installer, three orchestrators

    The pipeline, BNK Forge and Argo CD will all run the same installer. To guarantee that they run
    *exactly* the same code, the installer is packaged once as a **container image**, with kubectl,
    helm and yq at pinned versions inside it, and every orchestrator refers to that image by its
    **digest**, a fingerprint of its content.

    You build it, publish it to the lab's registry, write its digest into the repository, and merge
    that change. It is the smallest real change you can make, which makes it the right one to learn
    the pull-request flow on.
tabs:
- title: Terminal
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
- title: Lab Topology
  type: service
  hostname: lab
  port: 5050
difficulty: intermediate
timelimit: 2400
---

# Build the installer image and land your first pull request

---

## Step 1: Why an image, and why a digest

> ### Concept: container images and registries
> A **container image** is a frozen filesystem plus a start command: here, Debian with `kubectl`,
> `helm`, `yq`, `make`, `python3` and the installer in `/opt/bnk-host-deploy`. Images are stored in
> a **registry** (Docker Hub, GHCR, Harbor, or the plain `registry:2` this lab runs on port 5000),
> named like `registry/repository:tag`.

> ### Concept: tags move, digests do not
> A **tag** such as `:2.4.2` is a label someone can point at a different image tomorrow. A
> **digest** such as `@sha256:9f2c…` is the hash of the image's content: if one byte changes, the
> digest changes. Pinning by digest is how you prove, months later, exactly which build installed a
> cluster. BNK Forge goes further and **refuses** any module image that is not pinned by digest, or
> that runs as root.

Open `Dockerfile` in VS Code. Note the last lines: `USER 1000` and `ENTRYPOINT ["bnk-host"]`. Then
open `bin/bnk-host`: one verb per install phase (`preflight`, `prereqs`, `flo`, …), so an
orchestrator can run and report the install step by step.

---

## Step 2: Build, publish and pin

```run
lab image
```

Four things happen:

1. a registry starts on `localhost:5000` (the address the VM's Docker uses, and so Forge) and on
   `172.18.0.1:5000` (the address the cluster's nodes use, and so Argo CD's install job)
2. `docker build` produces the image from **your working copy**, with tool versions read from
   `versions.env`, and proves it runs as uid 1000
3. the image is pushed, and the registry's digest is read back
4. the digest is written into the two files that reference the image:
   `forge/bnk-host/bnkforge.artifact.json` and `argocd/bnk-install/job.yaml`

The `git diff --stat` at the end shows two changed files. That change is not in effect anywhere yet:
it is on your disk only.

---

## Step 3: Commit on a branch

In **VS Code**, open the **Source Control** view (the branch icon on the left, or `Ctrl+Shift+G`).
You will see the two modified files. Click one to see the diff: only the image line changed.

Create a branch and commit. The terminal way:

```run
cd /root/workspace/bnk-host-deploy
git checkout -b pin-runner-image
git commit -am "runner: pin the installer image built in this lab"
git push -u origin pin-runner-image
```

(Or in VS Code: click the branch name in the status bar > *Create new branch*, type a message, and
press *Commit*, then *Publish Branch*.)

> ### Concept: why a branch
> A **branch** is a line of commits separate from `main`. You can push it, run CI on it and discuss
> it, while `main` stays exactly what is deployed. Try pushing to `main` directly and Gitea refuses:
> `main` is protected so that every change is reviewed.

---

## Step 4: Open the pull request

In **Gitea**, open the repository. A banner offers to create a pull request from `pin-runner-image`.
Click **New Pull Request**, check that the base is `main`, give it a title such as *Pin the
installer image*, and create it.

On the pull request, open the **Checks** (or the repository's **Actions** tab): the `ci` workflow
started by itself. Click into the run and watch your runner execute it, job by job:

- `pinned tools`: the runner fetches the exact yq and shellcheck versions in `versions.env`
- `shell and YAML lint`, `CNEInstance renders…`, `cluster files are valid`: the tests you ran by
  hand in the previous challenge

Notice what does **not** run: `plan`. Your change touched only the image pin, not anything about how
or where BNK is installed, so there is nothing to plan. Workflows are triggered by *paths*, so a
runner is only woken for work that matters.

---

## Step 5: Merge

When `ci` is green, press **Merge**. Your commit is now on `main`.

> ### What you just practised
> Branch, push, pull request, automatic checks, review, merge. Every change to BNK from here on, a
> new cluster, a version upgrade, a network change, goes in exactly this way. The repository's
> history becomes the change log of your BNK estate.

Pull `main` back into your working copy so it matches:

```run
git checkout main && git pull -q && git log --oneline -3
```

Press **Check**: it confirms `main` now pins the image you built.
