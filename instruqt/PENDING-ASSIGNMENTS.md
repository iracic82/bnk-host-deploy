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

## Challenge 9 (Argo CD)
- lab argocd: step 2 waits 1-3 min silently on first image pull (now prints progress)
- Sync dialog: 4 objects (cm bnk-cluster-<hash>, ns, sa, crb); hook Job not listed by design -> assets/argocd-1-sync-dialog.png
- Tree during sync: Job (anchor = hook) + pods                                                 -> assets/argocd-2-hook-failed.png
  (keep as a "what a failed hook looks like / backoffLimit" teaching moment, or drop)
- Success: Synced + Sync OK, Job healthy, pod completed                                       -> assets/argocd-3-sync-ok.png
- Lesson box: kubectl in a pod has NO in-cluster fallback (tries localhost:8080); installer 1.0.2
  builds a kubeconfig from the service account token (tokenFile). Fixed in the image, so fresh
  tracks get it in the baked digest — no 1.0.2 rollout step needed for students.
- Fresh-track check: setup's pinned digest must be built from a commit >= 414c31e.

## Challenges 10-11
- add screenshots as the user plays them

## Challenge 10 (first traffic) — played 11:45, all green
- DONE locally: f5-bnkgateways (dashed) name; traceroute text (hop 2 IS the VIP, TMM terminates);
  RemoteAddr 172.18.0.250 = TMM internal self IP, SNAT automap / full proxy explanation.
- TODO: the delivery table confused the player (ran the Forge-only kubectl apply on the argocd path,
  before merging). Make the per-path instruction unmistakable: print the owner first
  (`lab owner` or gitea variable), and put "Forge path only" in its own callout.
  Merging the PR later is harmless: Argo's apps app adopts the same objects.
- Observed: 3 pods across 3 nodes; 12 requests 4/3/5; delete a pod -> 12x 200.
