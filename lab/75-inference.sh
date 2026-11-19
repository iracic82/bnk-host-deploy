#!/usr/bin/env bash
# The AI Inference tab (:5060), challenge 12: a console that sends requests through BNK's VIPs and
# shows the three simulated GPUs. Before challenge 12 it simply says there are no model servers yet.
source "$(dirname "$0")/lib.sh"
install -d /opt/lab-inference; cp "$(dirname "$0")/inference/server.py" "$(dirname "$0")/inference/index.html" /opt/lab-inference/
cat > /etc/systemd/system/lab-inference.service <<UNIT
[Unit]
Description=AI Inference tab on :${PORT_INFERENCE}
After=network-online.target docker.service
[Service]
Environment=KUBECONFIG=/root/.kube/config
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/bin/python3 /opt/lab-inference/server.py ${PORT_INFERENCE}
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl enable --now lab-inference >/dev/null 2>&1; systemctl restart lab-inference
ok "AI Inference tab on :${PORT_INFERENCE}"
