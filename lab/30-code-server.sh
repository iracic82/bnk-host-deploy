#!/usr/bin/env bash
# VS Code in the browser (code-server), opened on the learner's working copy. Its terminal is a root
# shell on the VM with kubectl and the kubeconfig, and its Source Control view drives the branch,
# commit and push of the pull-request flow.
source "$(dirname "$0")/lib.sh"
V="$CODE_SERVER_VERSION"
step "code-server ${V}"
if [[ "$(/opt/code-server/bin/code-server --version 2>/dev/null | head -1 | awk '{print $1}')" != "$V" ]]; then
  T=$(mktemp -d)
  curl -fsSL --retry 4 -o "$T/cs.tgz" "https://github.com/coder/code-server/releases/download/v${V}/code-server-${V}-linux-amd64.tar.gz"
  rm -rf /opt/code-server && mkdir -p /opt/code-server && tar -xzf "$T/cs.tgz" -C /opt/code-server --strip-components=1
  rm -rf "$T"
fi
mkdir -p /root/.local/share/code-server/User
cat > /root/.local/share/code-server/User/settings.json <<'JSON'
{
  "workbench.colorTheme": "Default Dark Modern",
  "workbench.startupEditor": "none",
  "security.workspace.trust.enabled": false,
  "git.enableSmartCommit": true,
  "git.confirmSync": false,
  "git.autofetch": true,
  "terminal.integrated.cwd": "/root/workspace/bnk-host-deploy",
  "files.exclude": { "**/.git": true },
  "redhat.telemetry.enabled": false,
  "yaml.schemas": {},
  "editor.minimap.enabled": false,
  "editor.renderWhitespace": "boundary"
}
JSON
/opt/code-server/bin/code-server --install-extension redhat.vscode-yaml >/dev/null 2>&1 || warn "YAML extension not installed (open-vsx unreachable); editing still works"
cat > /etc/systemd/system/code-server.service <<UNIT
[Unit]
Description=VS Code (code-server) on :${PORT_CODE}
After=network-online.target
[Service]
Environment=HOME=/root
Environment=KUBECONFIG=/root/.kube/config
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/.local/bin
ExecStart=/opt/code-server/bin/code-server --auth none --bind-addr 0.0.0.0:${PORT_CODE} --disable-telemetry --disable-update-check ${WORKSPACE}
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl enable --now code-server >/dev/null 2>&1; systemctl restart code-server
for _ in $(seq 1 30); do curl -fsS -o /dev/null "http://127.0.0.1:${PORT_CODE}/healthz" && break; sleep 1; done
ok "VS Code on :${PORT_CODE}, folder ${WORKSPACE}"
