#!/usr/bin/env bash
# lab runner: register a CI runner for platform/bnk-host-deploy, next to the cluster.
#
# A pipeline is only YAML until something runs it. On GitHub, hosted runners live on the internet
# and cannot reach a private cluster, so BNK installs run on a *self-hosted* runner that sits beside
# the cluster (or a hub runner holding kubeconfigs). The labels it registers with are what
# "runs-on: [self-hosted, bnk]" in .github/workflows matches. Same model here, with Gitea Actions.
source "$(dirname "$0")/../lib.sh"
V="$GITEA_RUNNER_VERSION"; IP=$(vm_ip); DIR=/var/lib/gitea-runner
REPO="${GITEA_ORG}/${GITEA_REPO}"

step "1/4  the runner binary (gitea-runner ${V}, checksum verified)"
if [[ "$(gitea-runner --version 2>/dev/null | awk '{print $NF}')" != "v${V}" && "$(gitea-runner --version 2>/dev/null | awk '{print $NF}')" != "${V}" ]]; then
  T=$(mktemp -d); f="gitea-runner-${V}-linux-amd64.xz"
  curl -fsSL --retry 4 -o "$T/$f" "https://gitea.com/gitea/runner/releases/download/v${V}/${f}"
  curl -fsSL --retry 4 -o "$T/$f.sha256" "https://gitea.com/gitea/runner/releases/download/v${V}/${f}.sha256"
  (cd "$T" && sha256sum -c "$f.sha256" >/dev/null) || fail "gitea-runner checksum mismatch"
  xz -dc "$T/$f" > /usr/local/bin/gitea-runner; chmod +x /usr/local/bin/gitea-runner; rm -rf "$T"
fi
ok "$(gitea-runner --version)"

step "2/4  a registration token, scoped to this one repository"
TOKEN=$(docker exec -u git gitea gitea actions generate-runner-token --scope "$REPO" 2>/dev/null | tail -1)
[[ -n "$TOKEN" ]] || fail "could not get a runner registration token"
ok "token issued for ${REPO} (single use, not shown)"

step "3/4  register with the labels the workflows ask for"
# capacity 2: a pull request's ci and plan run side by side (deploys stay serialized by their
# concurrency group). host executor: jobs run directly on this VM, where kubectl, helm and the kubeconfig already are.
# That is the "runner beside the cluster" pattern. Labels: self-hosted + bnk select it; ubuntu-latest
# lets the static checks in ci.yml run here too.
mkdir -p "$DIR"; cd "$DIR" || exit 1
if [[ ! -s .runner ]]; then
  gitea-runner generate-config > config.yaml
  yq -i '.runner.capacity = 2 | .runner.envs.KUBECONFIG = "/root/.kube/config" | .runner.envs.PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" | .runner.timeout = "2h" | .log.level = "info"' config.yaml
  gitea-runner -c config.yaml register --no-interactive --instance "http://${IP}:${PORT_GITEA}" --token "$TOKEN" \
    --name bnk-lab-runner --labels "self-hosted:host,bnk:host,ubuntu-latest:host" >/dev/null
fi
ok "registered as bnk-lab-runner, labels: self-hosted, bnk, ubuntu-latest (executor: host)"

step "4/4  run it as a service"
cat > /etc/systemd/system/gitea-runner.service <<UNIT
[Unit]
Description=Gitea Actions runner beside the BNK cluster
After=network-online.target docker.service
[Service]
WorkingDirectory=${DIR}
Environment=HOME=/root
ExecStart=/usr/local/bin/gitea-runner -c ${DIR}/config.yaml daemon
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl enable --now gitea-runner >/dev/null 2>&1; systemctl restart gitea-runner
for _ in $(seq 1 30); do
  st=$(gitea_api GET "/repos/${REPO}/actions/runners" 2>/dev/null | jq -r '.runners[]? | select(.name=="bnk-lab-runner") | .status' | head -1)
  [[ "$st" == online || "$st" == idle || "$st" == active ]] && break; sleep 2
done
ok "runner status in Gitea: ${st:-unknown}  (Repository Settings > Actions > Runners)"
