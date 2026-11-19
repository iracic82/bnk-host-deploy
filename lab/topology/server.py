#!/usr/bin/env python3
"""Topology tab: serves index.html and /api/status, a JSON snapshot of the lab read from kubectl,
docker and systemd every few seconds. Read-only; it never shows a secret."""
import json, subprocess, threading, time, os, sys
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

HERE = os.path.dirname(os.path.abspath(__file__))
ENV = dict(os.environ, KUBECONFIG=os.environ.get("KUBECONFIG", "/root/.kube/config"))
STATE = {"ts": 0}

def sh(cmd, timeout=8):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout, env=ENV).stdout.strip()
    except Exception:
        return ""

def kj(args):
    out = sh(f"kubectl {args} -o json")
    try:
        return json.loads(out) if out else {}
    except ValueError:
        return {}

def cond(obj, t):
    for c in (obj.get("status", {}) or {}).get("conditions", []) or []:
        if c.get("type") == t:
            return c.get("status")
    return None

def snapshot():
    s = {"ts": int(time.time())}
    nodes = kj("get nodes").get("items", [])
    s["nodes"] = [{"name": n["metadata"]["name"],
                   "ready": cond(n, "Ready") == "True",
                   "tmm": n["metadata"].get("labels", {}).get("app") == "f5-tmm",
                   "hugepages": n["status"].get("allocatable", {}).get("hugepages-2Mi", "0")} for n in nodes]
    flo = kj("-n f5-cne-core get deploy f5-lifecycle-operator")
    s["flo"] = (flo.get("status", {}) or {}).get("readyReplicas", 0) >= 1 if flo else False
    cne = kj("-n f5-bnk get cneinstance f5-bnk-instance")
    s["cne"] = {"present": bool(cne), "version": (cne.get("spec", {}) or {}).get("manifestVersion"),
                "available": cond(cne, "Available") == "True" if cne else False}
    lic = kj("-n f5-cne-core get license.k8s.f5net.com")
    items = lic.get("items", []) if lic else []
    s["license"] = (items[0].get("status", {}) or {}).get("state") if items else None
    pods = kj("-n f5-bnk get pods -l app=f5-tmm").get("items", [])
    s["tmm"] = [{"node": p["spec"].get("nodeName"), "ready": cond(p, "Ready") == "True"} for p in pods]
    gws = kj("get gateway -A").get("items", [])
    s["gateways"] = [{"name": f'{g["metadata"]["namespace"]}/{g["metadata"]["name"]}',
                      "address": ((g.get("status", {}) or {}).get("addresses") or [{}])[0].get("value"),
                      "programmed": cond(g, "Programmed") == "True"} for g in gws]
    gc = kj("get gatewayclass f5-gateway-class")
    s["gatewayclass"] = cond(gc, "Accepted") == "True" if gc else False
    running = sh("docker ps --format '{{.Names}}'").split()
    s["containers"] = {n: (n in running) for n in ["gitea", "edge-router", "client", "lab-registry", "forge-tab", "bnk-forge-backend"]}
    s["runner"] = sh("systemctl is-active gitea-runner") == "active"
    apps = kj("-n argocd get applications").get("items", [])
    s["argocd"] = {"installed": bool(sh("kubectl get ns argocd -o name")),
                   "apps": [{"name": a["metadata"]["name"], "sync": a.get("status", {}).get("sync", {}).get("status"),
                             "health": a.get("status", {}).get("health", {}).get("status")} for a in apps]}
    s["bgp"] = "Established" in sh("docker exec edge-router vtysh -c 'show bgp summary' 2>/dev/null", 5)
    return s

def loop():
    while True:
        try:
            STATE.update(snapshot())
        except Exception as e:  # keep serving the last good snapshot
            print("snapshot failed:", e, file=sys.stderr)
        time.sleep(5)

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def do_GET(self):
        if self.path.startswith("/api/status"):
            body, ctype = json.dumps(STATE).encode(), "application/json"
        else:
            body, ctype = open(os.path.join(HERE, "index.html"), "rb").read(), "text/html; charset=utf-8"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

if __name__ == "__main__":
    threading.Thread(target=loop, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", int(sys.argv[1]) if len(sys.argv) > 1 else 5050), H).serve_forever()
