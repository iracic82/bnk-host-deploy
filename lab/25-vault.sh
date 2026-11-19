#!/usr/bin/env bash
# The lab's secret store. The F5 Artifact Registry key and the licence arrive as Instruqt team
# secrets; setup writes them into one Kubernetes Secret, lab-vault/bnk-credentials, and shreds every
# file copy. It stands in for HashiCorp Vault or a cloud secret manager: the lab's steps copy values
# from it into the CI secrets, Forge's project secrets and Argo CD's Secret, piped, never printed.
source "$(dirname "$0")/lib.sh"
for f in cne_pull_64.json license.jwt; do [[ -s "$SECRETS_DIR/$f" ]] || fail "$SECRETS_DIR/$f missing"; done
kubectl create namespace lab-vault --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n lab-vault create secret generic bnk-credentials \
  --from-file=far_service_account_key="$SECRETS_DIR/cne_pull_64.json" \
  --from-file=bnk_license_jwt="$SECRETS_DIR/license.jwt" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n lab-vault label secret bnk-credentials app.kubernetes.io/part-of=lab-vault --overwrite >/dev/null
ok "lab-vault/bnk-credentials holds far_service_account_key and bnk_license_jwt"
