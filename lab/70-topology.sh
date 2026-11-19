#!/usr/bin/env bash
# The Lab Topology tab (:5050): a live diagram of this sandbox, green as things get built.
source "$(dirname "$0")/lib.sh"
install -d /opt/lab-topology; cp "$(dirname "$0")/topology/server.py" "$(dirname "$0")/topology/index.html" /opt/lab-topology/
cat > /etc/systemd/system/lab-topology.service <<UNIT
[Unit]
Description=Lab topology tab on :${PORT_TOPOLOGY}
After=network-online.target docker.service
[Service]
Environment=KUBECONFIG=/root/.kube/config
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/bin/python3 /opt/lab-topology/server.py ${PORT_TOPOLOGY}
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl enable --now lab-topology >/dev/null 2>&1; systemctl restart lab-topology
ok "topology on :${PORT_TOPOLOGY}"
