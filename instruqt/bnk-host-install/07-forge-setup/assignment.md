---
slug: forge-setup
type: challenge
title: "Path B, BNK Forge (1/2): install Forge and load the installer into it"
teaser: Install F5's BNK Forge, then teach it your installer. The repository becomes a Forge module
  source; the module runs your pinned image, one Forge step per install phase.
notes:
- type: text
  contents: |-
    ## BNK Forge

    **BNK Forge** is F5's deployment and lifecycle tool for BIG-IP Next for Kubernetes: a web
    console, an API and an MCP server for AI assistants, in front of an engine that runs
    deployments as **modules** (OpenTofu, Helm, Ansible, or any container you give it) and then
    operates what it deployed: health, drift, snapshots, upgrades, licensing.

    Forge does not need its own BNK installer. It can run **yours**: the repository you have been
    working on is also a Forge *module source*. `forge/bnk-host/bnkforge.artifact.json` tells Forge
    "run this digest-pinned image, with these argv steps, with these secrets mounted". The image is
    the one you pinned in challenge 4.

    **On path A or C?** Press **Skip** (here and on the next challenge).
tabs:
- title: Terminal
  type: terminal
  hostname: lab
- title: BNK Forge
  type: service
  hostname: lab
  port: 8090
- title: VS Code
  type: service
  hostname: lab
  port: 8444
- title: Lab Topology
  type: service
  hostname: lab
  port: 5050
difficulty: intermediate
timelimit: 3000
---

# Path B, BNK Forge (1/2): install Forge and load the installer into it

---

## Step 1: Install Forge

Forge ships as containers. Its README's Linux install is: take the release's `dist/` bundle, write
an `.env`, run `./install.sh`. That is exactly what this does, explained as it goes:

```run
lab forge
```

What you get, all on this VM (Docker, host networking):

| Container | Role |
|---|---|
| `bnk-forge-backend` | the REST API (FastAPI) the UI, the CLI and the MCP server all use |
| `bnk-forge-celery-worker`, `-2`, `-beat` | the engine: runs deployment steps and scheduled health checks |
| `bnk-forge-frontend`, `bnk-forge-proxy` | the React UI behind a TLS proxy on port 443 |
| `bnk-forge-postgres`, `bnk-forge-redis` | state and the task queue |
| `bnk-forge-docker-socket-proxy` | a **scoped** view of Docker: Forge launches module containers through it, never through the raw socket |
| `bnk-forge-mcp` | the MCP server, so AI assistants can drive Forge |

Three settings the step made, and why:
- **a strong per-sandbox database password** before first start (Postgres bakes it in at init)
- **the admin password** changed on first login (Forge forces it), now `admin` / the password printed
- **`localhost:5000` added to the registry allowlist**: Forge runs module images only from
  registries an admin allows, and only pinned by digest

It also set the repository variable `BNK_INSTALLER=forge`: the CI pipeline now stands aside for this
cluster.

Open the **BNK Forge** tab and sign in as `admin` with the password the step printed (also in
`/root/.lab/forge-password`).

---

## Step 2: Read the module before you load it

In **VS Code**, open `forge/bnk-host/bnkforge.artifact.json`. This is the contract Forge enforces:

| Block | What it says |
|---|---|
| `container_image` | registry `localhost:5000`, repository, and the **digest** you pinned. A tag would be rejected |
| `steps.apply` | ten steps, each `["bnk-host", "<phase>"]`: argv only, no shell. Forge refuses `sh -c` |
| `secret_files` | three project secrets Forge writes, mode 0600, into the runner's `/work/secrets`: `kubeconfig`, `far_service_account_key`, `bnk_license_jwt` |
| `inputs` | the deploy form: `tmm_node` is required, the rest has defaults |
| `cluster` | after a successful apply, register the cluster on Forge's **Kubernetes** page |

> ### Concept: the form is the cluster file
> `tmm_node` in Forge's form and `tmm.nodes` in `clusters/lab.yaml` are the same thing. The runner
> starts from the repository's `clusters/lab.yaml` (and its network files) and sets the node you
> type. Git or Forge, the cluster ends up described the same way.

---

## Step 3: Add the repository as a source

In Forge:

1. **Build > Modules**, open **Sources**, add a **git** source:
   - name `bnk-host-deploy`
   - URL: the repository's clone URL, shown by
     ```run
     echo "http://$(ip -4 route get 1.1.1.1 | sed -n 's/.* src \([0-9.]*\).*/\1/p'):3000/platform/bnk-host-deploy.git"
     ```
   - branch `main`

   Save and **Sync**. Forge clones the repository, finds `forge/bnk-host/bnkforge.pack.json`,
   validates it (pinned digest, allowlisted registry, argv-only steps, non-root image) and lists the
   module **BNK 2.4.2 Host install**.

2. **Build > Catalog**, open **Sources**, add the **same** URL as a blueprint source and **Sync**.
   Forge finds `forge/forge-blueprint.json` and shows the blueprint **BNK 2.4.2 Host on an existing
   cluster** as *discovered*.

3. On that blueprint, press **Import**. Discovered means "Forge has seen it"; imported means
   "deployable". Releases are immutable: change the blueprint and you must bump its version.

Prefer the API? The same three actions:

```run
lab forge-catalog
```

---

## Step 4: Create the project and attach the credentials

In **Build > Catalog**, deploy the imported blueprint into a **new project** named `bnk-lab`. The
form asks for `tmm_node`: enter `bnk-worker`. Leave `cluster_name` as `lab`. **Do not deploy yet.**

The project now needs the three secrets the module declared. They live in the lab vault, and the
values never reach your screen:

```run
lab forge-secrets bnk-lab
```

Open the project's **Secrets** tab in Forge: three entries, values hidden. Forge stores them
encrypted and materializes them only inside the runner container, for the length of a run.

> ### Concept: why the kubeconfig is a secret here
> The CI runner sits beside the cluster with its own access. Forge's runner is a short-lived
> container Forge starts; it gets cluster access only from the project's `kubeconfig` secret. The
> cluster's API server listens on this VM's address (not `127.0.0.1`) precisely so those
> containers can reach it.

Press **Check**: it confirms Forge is up, the blueprint is imported and project `bnk-lab` has its
three secrets.
