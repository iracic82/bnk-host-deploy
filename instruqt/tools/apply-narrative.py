#!/usr/bin/env python3
"""Replace the story parts of a challenge, keeping everything Instruqt manages.

    apply-narrative.py <challenge-dir> <narrative.md>

<narrative.md> holds a small header and the body:

    title: ...
    teaser: ...
    ===NOTE===
    first note (markdown)
    ===NOTE===
    second note
    ===BODY===
    # the assignment body

The challenge's ids, tabs, slug, difficulty and timelimit are left exactly as they are, so a push
updates the text without recreating anything.
"""
import sys
import yaml


class Literal(str):
    pass


def literal(dumper, data):
    return dumper.represent_scalar("tag:yaml.org,2002:str", data, style="|")


yaml.add_representer(Literal, literal)


def main(cdir, src):
    path = f"{cdir}/assignment.md"
    text = open(path).read()
    _, fm, _old_body = text.split("---\n", 2)
    meta = yaml.safe_load(fm)

    raw = open(src).read()
    head, rest = raw.split("===NOTE===", 1)
    parts = rest.split("===BODY===")
    notes, body = parts[0].split("===NOTE==="), parts[1].strip() + "\n"
    meta.update(yaml.safe_load(head) or {})   # title, teaser (may wrap onto indented lines)
    meta["notes"] = [{"type": "text", "contents": Literal(n.strip() + "\n")} for n in notes if n.strip()]

    order = ["slug", "id", "type", "title", "teaser", "notes", "tabs", "difficulty", "timelimit", "enhanced_loading"]
    ordered = {k: meta[k] for k in order if k in meta}
    ordered.update({k: v for k, v in meta.items() if k not in ordered})
    out = yaml.dump(ordered, sort_keys=False, allow_unicode=True, width=100)
    open(path, "w").write(f"---\n{out}---\n\n{body}")
    print(f"{path}: {len(ordered['notes'])} notes, {len(body.splitlines())} body lines")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
