# Pending assignment.md work (do at the end, after the full play-through; push to Instruqt only when approved)

## Global
- Narrative rewrite for 5-11 (drafts for 1-4 already applied locally); add scratchpad narr/06-tmm-inside.md section to challenge 6.

## Challenge 7 (Forge setup) — real UI flow + screenshots
1. lab forge, lab image, commit+merge pin (Gitea tab now present)
2. Catalog > Blueprints > **Sources** button > Blueprint Sources dialog > Add Blueprint Source  -> assets/forge-1-sources.png
   (or `lab forge-catalog`, which also adds the module source and imports)
3. Blueprint appears as `discovered` -> **Import**                                         -> assets/forge-2-discovered.png
4. Now `imported`, Deploy enabled                                                           -> assets/forge-3-imported.png
5. Deploy dialog: What you get / Prerequisites (3 secrets) / Modules                       -> assets/forge-4-deploy-dialog.png
6. Deployment Target: New Project `bnk-lab`, input "The node TMM runs on" = bnk-worker      -> assets/forge-5-deploy-target.png
7. Project created, module Pending, pipeline Waiting                                       -> assets/forge-6-project-pending.png
8. `lab forge-secrets bnk-lab` -> Secrets tab: Required Secrets (materialized to
   secrets/kubeconfig, secrets/cne_pull_64.json, secrets/license.jwt)                      -> assets/forge-7-secrets.png
   Explain FILE vs value secrets; Quick Import (FAR/JWT) buttons exist but students never see the files.

## Challenge 8 (Forge deploy) — restructure
- Deploy all; per-step log (10 containers, digest-pinned, non-root ✓)                      -> assets/forge-8-deployed.png
- Forge views of the result: Operate > Kubernetes (Cluster Ready, BNK installed)           -> assets/forge-9-cluster.png
  F5 BNK > Insights > Health Dashboard (Platform Healthy, 5/5 TMM, 2 VLANs)                -> assets/forge-10-bnk-health.png
- NEW section "Roll out a fixed installer": branch, lab image (new digest -> version 1.0.1),
  merge (BEFORE lab forge-catalog — sources track main), lab forge-catalog (v1.0.1),
  module ⋮ > Change Version > 1.0.1 > Deploy all; lesson: digest pinning + immutable catalog versions.
- Note: stale red "70 verify failed" banner stays from an earlier run; module status is authoritative.
- Investigate: Forge licence card shows "Unknown" though License CR is Active (check before ch 11).

## Challenges 9-11
- add screenshots as the user plays them (Argo CD next)
