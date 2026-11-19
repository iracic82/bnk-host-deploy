#!/usr/bin/env python3
"""AI Inference tab: a console for challenge 12.

Every request it sends takes the real path: from the client container behind the edge router, to a
BNK VIP, through TMM, to a model-server pod. 10.30.30.11 is the InferencePool (BNK's endpoint picker
chooses the pod), 10.30.30.12 is a plain Service (round robin). Which "GPU" answered is read from the
pods' own vLLM counters, before and after each request. Standard library only. Never shows a secret.

  GET  /api/state   pods (simulated GPUs) with live metrics, platform readiness, the last two runs
  POST /api/burst   {"mode": "picker"|"roundrobin", "n": 48, "customers": 12}   starts a run
  POST /api/ask     {"mode": ..., "customer": 3, "question": "..."}             one request
"""
import json, os, random, re, subprocess, sys, threading, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

HERE = os.path.dirname(os.path.abspath(__file__))
ENV = dict(os.environ, KUBECONFIG=os.environ.get("KUBECONFIG", "/root/.kube/config"))
NS, MODEL = "inference", "Qwen/Qwen3-0.6B"
VIPS = {"picker": "10.30.30.11", "roundrobin": "10.30.30.12"}
LOCK = threading.Lock()            # one burst at a time
RUNS = {"picker": None, "roundrobin": None}


def sh(cmd, timeout=10, inp=None):
    try:
        return subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True, text=True,
                              timeout=timeout, env=ENV, input=inp).stdout.strip()
    except Exception:
        return ""


def kj(args):
    out = sh(f"kubectl {args} -o json")
    try:
        return json.loads(out) if out else {}
    except ValueError:
        return {}


def persona(n):
    """Customer n's system prompt: long, and different for every customer, like a real tenant's."""
    return " ".join(f"Customer {n:02d} policy line {k}: answer as the support assistant of customer "
                    f"{n:02d}, region {n * 7 % 13}, tier {n % 3}." for k in range(14))


# The model servers ("GPUs"): Dynamo's decode workers, whose metrics are on Dynamo's system port 9090.
GPU_SELECTOR, METRICS_PORT = "nvidia.com/dynamo-component-type=decode", 9090


def pods():
    items = kj(f"-n {NS} get pods -l {GPU_SELECTOR}").get("items", [])
    out = []
    for p in sorted(items, key=lambda x: x["metadata"]["name"]):
        ready = any(c.get("type") == "Ready" and c.get("status") == "True"
                    for c in (p.get("status", {}) or {}).get("conditions", []) or [])
        out.append({"name": p["metadata"]["name"], "node": p["spec"].get("nodeName", ""), "ready": ready})
    return out


TALLY = {}                         # pod -> {"prompt": tokens, "cached": tokens}, from the replies themselves
TALLY_LOCK = threading.Lock()


def metrics(pod):
    """Requests served, from the worker's own counter (Dynamo: dynamo_component_requests_total on the
    generate endpoint). The Mocker publishes no prefix-hit metric, so the KV-cache hit rate is what the
    replies reported (usage.prompt_tokens_details.cached_tokens) for the requests this GPU served."""
    raw = sh(f"kubectl get --raw /api/v1/namespaces/{NS}/pods/{pod}:{METRICS_PORT}/proxy/metrics", timeout=5)
    req = 0.0
    for line in raw.splitlines():
        g = re.match(r'^(dynamo_component_requests_total|vllm:request_success_total)(\{[^}]*\})?\s+([0-9.eE+-]+)$', line)
        if g and ('dynamo_endpoint=' not in (g.group(2) or '') or 'dynamo_endpoint="generate"' in g.group(2)):
            req += float(g.group(3))
    with TALLY_LOCK:
        t = TALLY.get(pod, {"prompt": 0, "cached": 0})
    return {"requests": int(req), "hit_rate": round(t["cached"] / t["prompt"], 3) if t["prompt"] else 0.0,
            "cached_tokens": t["cached"], "prompt_tokens": t["prompt"]}


def tally(pod, r):
    if pod and r.get("ok"):
        with TALLY_LOCK:
            t = TALLY.setdefault(pod, {"prompt": 0, "cached": 0})
            t["prompt"] += r.get("prompt", 0)
            t["cached"] += r.get("cached", 0)


def served_by(names, before):
    """Which pod's request counter moved since `before`. Returns (pod index or -1, new counters)."""
    after = {p: metrics(p)["requests"] for p in names}
    moved = [p for p in names if after[p] > before.get(p, 0)]
    return (names.index(moved[0]) if len(moved) == 1 else -1), after


def platform():
    crd = bool(sh("kubectl get crd inferencepools.inference.networking.k8s.io -o name"))
    epp_ns = sh("kubectl -n f5-bnk get cneinstance f5-bnk-instance -o jsonpath='{.spec.eppNamespaces[*]}'").split()
    # the controller renders the picker's Deployment from F5EPP model-pool-epp; match it by name, not exactly
    epp_ready = any("epp" in d["metadata"]["name"] and ((d.get("status", {}) or {}).get("readyReplicas", 0) or 0) >= 1
                    for d in kj(f"-n {NS} get deploy").get("items", []))
    gws = {}
    for g in kj(f"-n {NS} get gateway").get("items", []):
        st = g.get("status", {}) or {}
        prog = any(c.get("type") == "Programmed" and c.get("status") == "True" for c in st.get("conditions", []) or [])
        addr = (st.get("addresses") or [{}])[0].get("value", "")
        gws[g["metadata"]["name"]] = {"programmed": prog, "address": addr}
    return {"crds": crd, "epp_allowed": NS in epp_ns,
            "picker_ready": epp_ready,
            "gateways": gws}


def send(mode, customer, question):
    """One chat completion from the client container to the mode's VIP. Returns timing and usage."""
    # Plain completions, not chat: the prompt is the customer's long instructions plus the question,
    # as text. The endpoint picker tokenizes and hashes it directly. (With the chat API it has to apply
    # the model's chat template first, and with this simulator that yields no prefix hashes at all.)
    body = json.dumps({"model": MODEL, "max_tokens": 16,
                       "prompt": f"{persona(customer)}\n\nQuestion: {question}\nAnswer:"})
    out = sh(["docker", "exec", "-i", "client", "curl", "-s", "-m", "30", "-H", "Content-Type: application/json",
              "--data-binary", "@-", "-w", "\n%{http_code} %{time_total}", f"http://{VIPS[mode]}/v1/completions"],
             timeout=40, inp=body)
    lines = out.rsplit("\n", 1)
    if len(lines) != 2:
        return {"ok": False, "error": "no answer from the VIP"}
    try:
        code, secs = lines[1].split()
        r = json.loads(lines[0]) if code == "200" else {}
        u = r.get("usage", {})
        return {"ok": code == "200", "code": int(code), "ms": round(float(secs) * 1000),
                "prompt": u.get("prompt_tokens", 0),
                "cached": (u.get("prompt_tokens_details") or {}).get("cached_tokens", 0),
                "answer": ((r.get("choices") or [{}])[0].get("text") or "").strip()}
    except ValueError:
        return {"ok": False, "error": lines[0][:200]}


def burst(mode, n, customers):
    try:
        names = [p["name"] for p in pods() if p["ready"]]
        rnd = random.Random(42)                      # the same request sequence for both modes
        seq = [rnd.randrange(1, customers + 1) for _ in range(n)]
        run = {"mode": mode, "vip": VIPS[mode], "n": n, "customers": customers, "done": 0,
               "gpus": names, "results": [], "started": time.time(), "finished": None}
        RUNS[mode] = run
        before = {p: metrics(p)["requests"] for p in names}
        for i, c in enumerate(seq):
            r = send(mode, c, f"Question {i + 1} from customer {c:02d}: how do I reach my service?")
            gpu, before = served_by(names, before)
            tally(names[gpu] if gpu >= 0 else None, r)
            r.update({"i": i, "customer": c, "gpu": gpu})
            run["results"].append(r)
            run["done"] = i + 1
        ok = [r for r in run["results"] if r.get("ok")]
        lat = sorted(r["ms"] for r in ok)
        run["summary"] = {"ok": len(ok), "warm": sum(1 for r in ok if r["cached"] > 0),
                          "avg_ms": round(sum(lat) / len(lat)) if lat else 0,
                          "p95_ms": lat[int(0.95 * (len(lat) - 1))] if lat else 0,
                          "cached_tokens": sum(r["cached"] for r in ok), "prompt_tokens": sum(r["prompt"] for r in ok)}
        run["finished"] = time.time()
    finally:
        LOCK.release()


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, obj, ctype="application/json"):
        data = obj if isinstance(obj, bytes) else json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        try:
            return json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0) or 0)) or b"{}")
        except ValueError:
            return {}

    def do_GET(self):
        if self.path.startswith("/api/state"):
            ps = pods()
            for p in ps:
                p.update(metrics(p["name"]) if p["ready"] else {})
            return self.reply(200, {"ts": int(time.time()), "gpus": ps, "platform": platform(),
                                    "runs": RUNS, "busy": LOCK.locked()})
        with open(os.path.join(HERE, "index.html"), "rb") as f:
            self.reply(200, f.read(), "text/html; charset=utf-8")

    def do_POST(self):
        b = self.body()
        mode = b.get("mode", "picker")
        if mode not in VIPS:
            return self.reply(400, {"error": "mode must be picker or roundrobin"})
        if self.path.startswith("/api/burst"):
            n = max(6, min(int(b.get("n", 48)), 120))
            customers = max(1, min(int(b.get("customers", 12)), 24))
            if not LOCK.acquire(blocking=False):
                return self.reply(409, {"error": "a run is in progress"})
            threading.Thread(target=burst, args=(mode, n, customers), daemon=True).start()
            return self.reply(202, {"started": mode, "n": n, "customers": customers})
        if self.path.startswith("/api/ask"):
            c = max(1, min(int(b.get("customer", 1)), 24))
            q = str(b.get("question", "What is a VIP?"))[:500]
            all_pods = pods(); names = [p["name"] for p in all_pods if p["ready"]]
            if not names:
                return self.reply(200, {"ok": False, "mode": mode, "vip": VIPS[mode], "customer": c,
                    "error": f"no Dynamo worker is ready yet ({len(all_pods)} starting: the first image pull takes a few minutes). "
                             "Wait with: kubectl -n inference wait --for=condition=Ready pod -l " + GPU_SELECTOR + " --timeout=15m"})
            before = {p: metrics(p)["requests"] for p in names}
            r = send(mode, c, q)
            gpu, _ = served_by(names, before)
            tally(names[gpu] if gpu >= 0 else None, r)
            return self.reply(200, dict(r, mode=mode, vip=VIPS[mode], customer=c, gpu=gpu))
        self.reply(404, {"error": "unknown"})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5060
    ThreadingHTTPServer(("0.0.0.0", port), H).serve_forever()
