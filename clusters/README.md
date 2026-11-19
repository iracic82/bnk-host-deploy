# clusters/

One file per cluster. The file answers **where** BNK goes; `versions.env` answers **what** is
installed and `environments/<env>.env` answers **how strictly**.

| Field | Meaning |
|---|---|
| `name` | must equal the file name |
| `environment` | `lab`, `staging` or `production`, a file in `environments/` |
| `kube_context` | the kubectl context the runner uses for this cluster |
| `storage_class` | where BNK's stateful components (DSSM, CWC) keep their volumes |
| `pod_cidr` | the CNI's pod range, excluded from TMM routing by pseudoCNI |
| `tmm.nodes` | exactly one node that runs TMM; it must offer 2Mi hugepages |
| `tmm.manage_labels` | `true`: the installer applies `app=f5-tmm` to that node |
| `watch_namespaces` | optional; empty means BNK watches the whole cluster |
| `enabled` | `true`: the deploy job installs BNK here when this file changes on `main` |

The deploy workflow only acts on cluster files a merge actually changed, so a pull request that
touches `clusters/lab.yaml` can never install anything on another cluster.

Validate a file locally: `./tests/cluster.sh clusters/lab.yaml`
