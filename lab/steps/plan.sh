#!/usr/bin/env bash
# lab plan [cluster file]: what would installing main's version of the repository change on the live
# cluster? Runs the pinned runner image in plan mode with the vault's FAR key (in a temp file,
# 0600, removed after). Read-only: nothing in the cluster changes.
source "$(dirname "$0")/../lib.sh"
f="${1:-clusters/lab.yaml}"
d=$(cat "$LAB_STATE/runner-digest" 2>/dev/null) || fail "no runner image yet: run 'lab image'"
T=$(mktemp -d); chmod 700 "$T"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/secrets" "$T/clusters"
vault_get far_service_account_key > "$T/secrets/cne_pull_64.json"; cp /root/.lab/kubeconfig-forge.yaml "$T/secrets/kubeconfig"
cp "$WORKSPACE/$f" "$WORKSPACE/${f%.yaml}".*.yaml "$T/clusters/" 2>/dev/null || true
chown -R 1000:1000 "$T"
docker run --rm -v "$T:/work" -e BNK_CLUSTER_FILE="/work/clusters/$(basename "$f")" -e KUBE_CONTEXT= \
  "localhost:${PORT_REGISTRY}/bnk-host-deploy@${d}" plan
