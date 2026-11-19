#!/usr/bin/env python3
"""Flow diagrams for the track's assignments, as SVG and PNG (assets/diag-*.png).

Instruqt renders GitHub-flavoured Markdown without Mermaid, so the diagrams are drawn here, in the
same style as edge-topology.svg, and embedded as images. Edit a diagram below and run:

    python3 instruqt/tools/diagrams.py
"""
import os
from xml.sax.saxutils import escape

import cairosvg

OUT = os.path.join(os.path.dirname(__file__), "..", "bnk-host-install", "assets")
FONT = "Inter, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"

STYLES = {
    #          fill       stroke     title      sub
    "git":    ("#f3f6ff", "#3b5bdb", "#1c2b6b", "#4a5a8a"),
    "ci":     ("#effaf3", "#2f9e44", "#1b5e2b", "#4a7a55"),
    "forge":  ("#fff4e6", "#e8590c", "#7a2e05", "#8a5a3a"),
    "argo":   ("#f3f0ff", "#7048e8", "#35207a", "#5f5290"),
    "bnk":    ("#fff1f3", "#e4002b", "#7a0016", "#8a4a55"),
    "k8s":    ("#eef7ff", "#1971c2", "#0b3a66", "#4a6a8a"),
    "person": ("#f8f9fa", "#495057", "#212529", "#6c757d"),
    "net":    ("#f1fbfb", "#0c8599", "#06454f", "#4a7a80"),
}


def box(x, y, w, h, title, sub="", style="git", dashed=False):
    fill, stroke, tc, sc = STYLES[style]
    dash = ' stroke-dasharray="7 5"' if dashed else ""
    out = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{fill}" stroke="{stroke}" stroke-width="2.2"{dash}/>']
    lines = sub.split("\n") if sub else []
    ty = y + h / 2 - (len(lines) * 9) + (6 if not lines else 0)
    out.append(f'<text x="{x + w / 2}" y="{ty}" text-anchor="middle" font-size="17" font-weight="700" fill="{tc}">{escape(title)}</text>')
    for i, ln in enumerate(lines):
        out.append(f'<text x="{x + w / 2}" y="{ty + 21 + i * 18}" text-anchor="middle" font-size="13.5" fill="{sc}">{escape(ln)}</text>')
    return "\n".join(out)


def arrow(x1, y1, x2, y2, label="", color="#868e96", dashed=False, lx=None, ly=None, bend=None):
    dash = ' stroke-dasharray="6 5"' if dashed else ""
    if bend:  # orthogonal path through a list of points
        pts = [(x1, y1)] + bend + [(x2, y2)]
        d = "M" + " L".join(f"{px},{py}" for px, py in pts)
    else:
        d = f"M{x1},{y1} L{x2},{y2}"
    out = [f'<path d="{d}" fill="none" stroke="{color}" stroke-width="2.2"{dash} marker-end="url(#a-{color[1:]})"/>']
    if label:
        lx = (x1 + x2) / 2 if lx is None else lx
        ly = (y1 + y2) / 2 - 8 if ly is None else ly
        for i, ln in enumerate(label.split("\n")):
            wpx = len(ln) * 7.0 + 10
            out.append(f'<rect x="{lx - wpx / 2}" y="{ly + i * 16 - 13}" width="{wpx}" height="17" fill="#ffffff"/>')
            out.append(f'<text x="{lx}" y="{ly + i * 16}" text-anchor="middle" font-size="13" fill="#495057">{escape(ln)}</text>')
    return "\n".join(out)


def note(x, y, text, size=13, color="#6c757d", anchor="start", weight="400"):
    return "\n".join(
        f'<text x="{x}" y="{y + i * (size + 4)}" text-anchor="{anchor}" font-size="{size}" font-weight="{weight}" fill="{color}">{escape(ln)}</text>'
        for i, ln in enumerate(text.split("\n")))


def band(x, y, w, h, label, color="#dee2e6"):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="16" fill="none" stroke="{color}" stroke-width="2" stroke-dasharray="4 6"/>'
            f'<text x="{x + 14}" y="{y + 22}" font-size="13" font-weight="700" fill="#868e96" letter-spacing="1">{escape(label.upper())}</text>')


def svg(name, w, h, title, body):
    colors = {"#868e96", "#e4002b", "#2f9e44", "#e8590c", "#7048e8", "#1971c2", "#3b5bdb", "#0c8599"}
    markers = "".join(
        f'<marker id="a-{c[1:]}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
        f'<path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker>' for c in colors)
    doc = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" font-family="{FONT}">'
           f'<defs>{markers}</defs><rect width="{w}" height="{h}" fill="#ffffff"/>'
           f'<text x="28" y="40" font-size="21" font-weight="800" fill="#212529">{escape(title)}</text>'
           f'<rect x="28" y="50" width="56" height="4" rx="2" fill="#e4002b"/>{body}</svg>')
    path = os.path.join(OUT, f"diag-{name}.svg")
    open(path, "w").write(doc)
    cairosvg.svg2png(bytestring=doc.encode(), write_to=path[:-4] + ".png", output_width=w * 2)
    print("wrote", path[:-4] + ".png")


# ---------------------------------------------------------------------------------------------------
def three_paths():
    b = [box(40, 250, 210, 90, "the repository", "clusters/lab.yaml\nversions.env, lib/", "git"),
         box(40, 380, 210, 70, "the pinned image", "bnk-host-deploy@sha256", "git")]
    rows = [(110, "A. CI/CD pipeline", "plan on the pull request\ndeploy on the merge", "ci", "challenges 5 and 6"),
            (255, "B. BNK Forge", "catalog, project, form\none container per step", "forge", "challenges 7 and 8"),
            (400, "C. Argo CD", "sync a Job from git\ninside the cluster", "argo", "challenge 9")]
    for y, t, s, st, ch in rows:
        b.append(box(400, y, 270, 90, t, s, st))
        b.append(note(535, y + 110 - 2, ch, 12.5, "#868e96", "middle"))
        b.append(arrow(250, 295, 398, y + 45, color="#868e96"))
        b.append(arrow(670, y + 45, 838, 290, color="#868e96"))
    b.append(box(840, 235, 230, 110, "cluster six", "BNK 2.4.2, TMM on bnk-worker\nsame result, any path", "bnk"))
    b.append(box(840, 395, 230, 70, "challenge 10", "first traffic, together", "k8s", dashed=True))
    b.append(arrow(955, 345, 955, 393, color="#e4002b"))
    svg("three-paths", 1110, 530, "Three drivers, one installer, one cluster", "\n".join(b))


def cicd_flow():
    b = [band(20, 80, 1180, 170, "pull request: nothing changes yet"),
         band(20, 290, 1180, 170, "merge: the install")]
    b += [box(50, 130, 180, 90, "you", "edit clusters/lab.yaml\non a branch", "person"),
          box(290, 130, 200, 90, "pull request", "Install BNK on\nthe lab cluster", "git"),
          box(550, 130, 260, 90, "plan.yml", "server-side dry run\nagainst the real cluster", "ci"),
          box(870, 130, 290, 90, "plan comment", "N planned changes\none row per phase + guide", "ci"),
          box(870, 340, 290, 90, "reviewer", "right cluster? version? node?\nthen Merge", "person"),
          box(550, 340, 260, 90, "deploy.yml", "phases 00 to 70\nsame image, same order", "ci"),
          box(50, 340, 440, 90, "cluster six", "BNK Available, provenance stamped", "bnk")]
    b += [arrow(230, 175, 288, 175), arrow(490, 175, 548, 175, "push"), arrow(810, 175, 868, 175, "posts"),
          arrow(1015, 220, 1015, 338, "reads", color="#868e96", lx=1050, ly=285),
          arrow(870, 385, 812, 385, "merge", color="#2f9e44", lx=841, ly=372),
          arrow(550, 385, 492, 385, color="#e4002b")]
    svg("cicd-flow", 1220, 490, "Path A: the plan is reviewed, the merge installs", "\n".join(b))


def install_phases():
    phases = [("00", "preflight", "checks only"), ("05", "nodes", "label, hugepages"), ("10", "prereqs", "Multus, cert-manager\nCA issuer"),
              ("20", "registry", "FAR login\npull secrets"), ("30", "FLO", "the operator"), ("40", "certs", "CWC, OTEL"),
              ("45", "attachments", "TMM's two NICs"), ("50", "CNEInstance", "~80 components"), ("55", "network", "VLANs, VIP pool"),
              ("60", "licence", "connected mode"), ("65", "ready", "TMM starts"), ("70", "verify", "guide's Expect lines")]
    b = []
    for i, (n, t, s) in enumerate(phases):
        col, row = i % 6, i // 6
        x, y = 40 + col * 195, 100 + row * 170
        st = "bnk" if n in ("50", "65") else ("k8s" if n in ("05", "10", "45", "55") else "ci")
        b.append(box(x, y, 165, 100, f"{n}  {t}", s, st))
        if col < 5:
            b.append(arrow(x + 165, y + 50, x + 193, y + 50))
    b.append(arrow(40 + 5 * 195 + 82, 200, 122, 268, color="#868e96", bend=[(40 + 5 * 195 + 82, 235), (122, 235)]))
    for i, (st, txt) in enumerate((("ci", "install steps"), ("k8s", "Kubernetes plumbing for TMM"), ("bnk", "where BNK comes alive"))):
        fill, stroke, _, _ = STYLES[st]
        x = 40 + i * 260
        b.append(f'<rect x="{x}" y="436" width="18" height="18" rx="4" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')
        b.append(note(x + 28, 450, txt, 13.5))
    svg("install-phases", 1230, 475, "The install, phase by phase (one file in lib/ and one F5 guide page each)", "\n".join(b))


def forge_flow():
    b = [box(40, 120, 200, 100, "Gitea repository", "forge/bnk-host/*.json\nforge/forge-blueprint.json", "git"),
         box(310, 120, 220, 100, "Forge catalog", "module source\nblueprint source, imported", "forge"),
         box(600, 120, 220, 100, "project bnk-lab", "form: tmm_node\n3 file secrets", "forge"),
         box(890, 120, 250, 100, "runner containers", "your image, by digest\none per step, non-root", "forge"),
         box(890, 300, 250, 100, "cluster six", "BNK 2.4.2\nregistered in Forge", "bnk"),
         box(600, 300, 220, 100, "lab vault", "FAR key, licence\nkubeconfig", "person", dashed=True)]
    b += [arrow(240, 170, 308, 170, "sources"), arrow(530, 170, 598, 170, "Deploy"), arrow(820, 170, 888, 170, "Deploy all"),
          arrow(1015, 220, 1015, 298, "kubeconfig", color="#e4002b", lx=1060, ly=262),
          arrow(710, 300, 710, 222, "lab forge-secrets", color="#868e96", lx=770, ly=262)]
    b.append(note(40, 440, "Forge never holds kubectl, helm or the installer itself. It starts your pinned image, step by step.", 13.5))
    svg("forge-flow", 1180, 465, "Path B: from git to a Forge project to the cluster", "\n".join(b))


def forge_steps():
    steps = ["preflight", "nodes", "prereqs", "registry", "flo", "certs", "cneinstance", "license", "ready", "verify"]
    b = [box(40, 110, 230, 110, "Forge engine", "reads steps.apply\nfrom the artifact", "forge")]
    for i, s in enumerate(steps):
        x, y = 320 + (i % 5) * 172, 95 + (i // 5) * 120
        b.append(box(x, y, 150, 80, s, "bnk-host " + s + "\n@sha256 digest", "forge", dashed=(s == "cneinstance")))
        if i % 5 < 4:
            b.append(arrow(x + 150, y + 40, x + 170, y + 40))
    b.append(arrow(270, 165, 318, 135))
    b.append(arrow(320 + 4 * 172 + 75, 175, 395, 213, color="#868e96", bend=[(320 + 4 * 172 + 75, 195), (395, 195)]))
    b.append(note(320, 340, "Each box is a new container from the same digest. A failed step shows its own log,\n"
                            "and Retry starts again from that step with the same workspace.", 13.5))
    svg("forge-steps", 1210, 390, "Why one container per step", "\n".join(b))


def argo_flow():
    b = [box(40, 120, 220, 100, "git: main", "clusters/lab*.yaml\nargocd/bnk-install/", "git"),
         box(340, 120, 240, 100, "Argo CD", "polls git, renders\nkustomize, compares", "argo"),
         box(660, 70, 250, 80, "ConfigMap", "bnk-cluster-<hash>", "k8s"),
         box(660, 175, 250, 80, "Job bnk-install (hook)", "your image, args: install", "argo"),
         box(1000, 165, 200, 100, "cluster six", "BNK 2.4.2", "bnk"),
         box(660, 300, 250, 90, "Secret", "bnk-install-credentials\nfrom the vault, not git", "person", dashed=True)]
    b += [arrow(260, 170, 338, 170, "watch"), arrow(580, 150, 658, 110), arrow(580, 190, 658, 215, "Sync"),
          arrow(785, 150, 785, 173, color="#868e96"), arrow(785, 300, 785, 257, "mounted", color="#868e96", lx=835, ly=283),
          arrow(910, 215, 998, 215, "service\naccount", color="#e4002b", lx=955, ly=245)]
    b.append(note(40, 440, "Change clusters/lab.yaml in git, the ConfigMap's hash changes, Argo shows OutOfSync. Nothing reaches in from outside.", 13.5))
    svg("argo-flow", 1230, 465, "Path C: the cluster pulls its desired state from git", "\n".join(b))


def traffic():
    b = [band(20, 80, 450, 330, "Sam's network"), band(500, 80, 720, 330, "cluster six")]
    b += [box(50, 140, 170, 80, "client", "10.20.20.10", "person"),
          box(270, 140, 170, 80, "edge router", "10.20.20.254\n10.10.10.254", "net"),
          box(540, 120, 260, 130, "TMM", "VIP 10.30.30.10:80\nexternal 10.10.10.11 (1.1)\ninternal 172.18.0.250 (1.2)", "bnk"),
          box(900, 100, 150, 60, "hello pod 1", "", "k8s"), box(900, 175, 150, 60, "hello pod 2", "", "k8s"),
          box(900, 250, 150, 60, "hello pod 3", "", "k8s"),
          box(540, 300, 260, 80, "BNK controller", "Gateway + HTTPRoute\nbecome a virtual server", "bnk", dashed=True)]
    b += [arrow(220, 180, 268, 180), arrow(440, 180, 538, 180),
          arrow(800, 165, 898, 130), arrow(800, 185, 898, 205), arrow(800, 205, 898, 280),
          arrow(670, 300, 670, 252, "programs", color="#868e96", lx=715, ly=283)]
    b.append(note(270, 250, "route 10.30.30.0/24\nvia 10.10.10.11 (TMM)", 13, "#495057"))
    b.append(note(50, 300, "connection 1\nclient to VIP", 13, "#0c8599", weight="700"))
    b.append(note(860, 350, "connection 2\nTMM (SNAT 172.18.0.250) to pod IP", 13, "#e4002b", weight="700"))
    svg("traffic", 1240, 440, "First traffic: two connections, TMM in the middle (full proxy)", "\n".join(b))


def day2():
    b = [box(40, 110, 270, 110, "git: what should be", "versions.env, clusters/\napps/, review history", "git"),
         box(470, 110, 270, 110, "cluster six: what is", "CNEInstance + annotations\nledger ConfigMap", "bnk"),
         box(900, 110, 280, 110, "BNK Forge: the auditor", "versions, health, gateways\nsnapshots, drift", "forge"),
         box(470, 300, 270, 90, "lab plan", "no changes = matches git", "ci")]
    b += [arrow(310, 165, 468, 165, "PR + delivery"), arrow(740, 165, 898, 165, "reads (kubeconfig)", color="#e4002b"),
          arrow(605, 220, 605, 298, color="#868e96"), arrow(470, 345, 175, 222, "compares", color="#868e96", bend=[(175, 345)])]
    svg("day2", 1220, 420, "Day 2: git says what should be, the cluster records what is, Forge audits it", "\n".join(b))


def inference():
    b = [band(20, 80, 330, 330, "Sam's network"), band(370, 80, 860, 330, "cluster six")]
    b += [box(35, 150, 155, 80, "customer 07", "long system prompt\n+ question", "person"),
          box(210, 150, 125, 80, "edge router", "", "net"),
          box(400, 130, 230, 120, "TMM", "VIP 10.30.30.11:80\nHTTPRoute to\nInferencePool", "bnk"),
          box(400, 300, 230, 90, "BNK endpoint picker", "F5EPP: prefix + load\nwhich GPU holds it?", "bnk", dashed=True),
          box(760, 95, 220, 70, "GPU A", "KV: cust 02, 04, 10", "k8s"),
          box(760, 185, 220, 70, "GPU B", "KV: cust 05, 07, 09", "k8s"),
          box(760, 275, 220, 70, "GPU C", "KV: cust 03, 06, 11", "k8s"),
          box(1010, 150, 200, 110, "warm hit", "prefill skipped\n~50 ms, not ~700 ms", "ci")]
    b += [arrow(190, 190, 208, 190), arrow(335, 190, 398, 190),
          arrow(470, 250, 470, 298, "asks", color="#e4002b", lx=495, ly=280),
          arrow(560, 298, 560, 252, "GPU B", color="#e4002b", lx=600, ly=280),
          arrow(630, 190, 758, 220, color="#e4002b"), arrow(980, 220, 1008, 205, color="#2f9e44")]
    b.append(note(400, 438, "Round robin (VIP .12) ignores who holds which prompt: most requests land on a GPU that must prefill from scratch.", 13.5))
    svg("inference", 1240, 460, "AI inference: BNK picks the GPU that already holds your prompt", "\n".join(b))


if __name__ == "__main__":
    for f in (three_paths, cicd_flow, install_phases, forge_flow, forge_steps, argo_flow, traffic, day2, inference):
        f()
