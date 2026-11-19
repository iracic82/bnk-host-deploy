#!/usr/bin/env bash
# lab argocd: install Argo CD ${ARGOCD_VERSION} into the cluster and point it at the repository.
#
# Argo CD is a controller that keeps the cluster equal to git. CI pushes changes into a cluster;
# Argo CD pulls them: it watches the repo, shows any difference as "OutOfSync", and on sync makes
# the cluster match. Two Applications come from argocd/applications/:
#   bnk-install  runs the installer (argocd/bnk-install, a Sync hook Job), when you press Sync
#   apps         owns apps/: auto-sync with self-heal, so hand edits are put back
source "$(dirname "$0")/../lib.sh"
IP=$(vm_ip); REPO_URL="http://${IP}:${PORT_GITEA}/${GITEA_ORG}/${GITEA_REPO}.git"

step "1/5  Argo CD ${ARGOCD_VERSION} (the upstream install manifest, server-side apply for its big CRDs)"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply --server-side --force-conflicts -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" >/dev/null
ok "manifests applied"

step "2/5  settings: plain HTTP behind the tab, kustomize may read clusters/ from the repo root"
kubectl -n argocd patch cm argocd-cmd-params-cm --type merge -p '{"data":{"server.insecure":"true"}}' >/dev/null
kubectl -n argocd patch cm argocd-cm --type merge -p '{"data":{"kustomize.buildOptions":"--load-restrictor LoadRestrictionsNone","timeout.reconciliation":"60s"}}' >/dev/null
kubectl -n argocd rollout restart deploy/argocd-server deploy/argocd-repo-server sts/argocd-application-controller >/dev/null
echo "      waiting for the Argo CD pods (first start pulls their images: 1-3 minutes)"
for d in argocd-server argocd-repo-server argocd-applicationset-controller; do
  kubectl -n argocd rollout status deploy/$d --timeout=300s >/dev/null && echo "      ready: $d"
done
kubectl -n argocd rollout status sts/argocd-application-controller --timeout=300s >/dev/null
ok "Argo CD running: $(kubectl -n argocd get pods --no-headers | grep -c Running) pods"

step "3/5  the install Job's credentials, from the lab vault (never in git)"
kubectl create namespace bnk-installer --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n bnk-installer create secret generic bnk-install-credentials \
  --from-file=cne_pull_64.json=<(vault_get far_service_account_key) \
  --from-file=license.jwt=<(vault_get bnk_license_jwt) --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "bnk-installer/bnk-install-credentials (cne_pull_64.json, license.jwt)"

step "4/5  the Applications, pointed at ${REPO_URL}"
for a in bnk-install apps; do
  sed "s|REPO_URL|${REPO_URL}|" "${WORKSPACE}/argocd/applications/${a}.yaml" | kubectl apply -f - >/dev/null
  ok "Application $a"
done

step "5/5  the Argo CD tab (:${PORT_ARGOCD})"
cat > /etc/systemd/system/argocd-tab.service <<UNIT
[Unit]
Description=Argo CD UI on :${PORT_ARGOCD}
After=network-online.target
[Service]
Environment=KUBECONFIG=/root/.kube/config
ExecStart=/usr/local/bin/kubectl -n argocd port-forward --address 0.0.0.0 svc/argocd-server ${PORT_ARGOCD}:80
Restart=always
RestartSec=2
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl enable --now argocd-tab >/dev/null 2>&1; systemctl restart argocd-tab
pw=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
echo "$pw" > /root/.lab/argocd-password; chmod 600 /root/.lab/argocd-password
ok "open the Argo CD tab: admin / $pw"

set_owner argocd
