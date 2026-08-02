#!/usr/bin/env python3
"""Company Brain OS memory gate: read-only health check for memory/.

Read-only: analyzes memory/ and prints JSON findings. Never writes to the
files it watches.

Exit: 0 = ok (or findings present without --strict); 1 = --strict with
blocking findings not allowlisted; 2 = execution error.
See docs/ADVANCED.md.

Definitions: nodes = active memory/*.md files (non-nodes excluded); edges =
[[wikilink]]s in the bodies of ACTIVE files (archive files count only as
valid link targets); ORPHAN = a project/strategic node with zero incoming
links; ISLAND = a component of >=2 nodes outside the nucleus with at least
one project/strategic node (singletons are already ORPHAN, no double
reporting).
"""
import argparse, datetime as dt, hashlib, json, os, re, subprocess, sys

LIMIT_BYTES = int(os.environ.get("MEMORY_GATE_LIMIT_BYTES", "24986"))  # 24.4 KiB auto-load
BUDGET_WARN_RATIO = 0.90
NON_NODES = {"MEMORY.md", "CLAUDE.md", "INDEX.generated.md"}
EXEMPT_TYPES = {"reference", "feedback"}
ALL_CHECKS = ["BROKEN", "ORPHAN", "ISLAND", "INDEX-ROW", "BUDGET", "STALE-INDEX",
              "DUP-STEM", "UNTYPED"]
VALID_TYPES = {"project", "strategic", "reference", "feedback"}
WIKILINK = re.compile(r"\[\[([A-Za-z0-9_\-]+)\]\]")
EMOJI = re.compile("[\U0001F534\U0001F7E0\U0001F7E1\U0001F7E2\U0001F535❌]")
LINK_ROW = re.compile(r"^- \[[^\]]+\]\(((?:archive/)?[A-Za-z0-9_\-]+\.md)\)")


def fail(msg):
    print(f"memory_gate: {msg}", file=sys.stderr)
    sys.exit(2)


def parse_iso(s, what):
    try:
        return dt.date.fromisoformat(s)
    except ValueError:
        fail(f"{what} is not valid: {s!r} (expected YYYY-MM-DD)")


def finding(check, target, severity, blocking, detail):
    return {"id": f"{check}:{target}", "check": check, "target": target,
            "severity": severity, "blocking": blocking, "detail": detail}


def split_frontmatter(text):
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---", 4)
    if end == -1:
        return {}, text
    fm = {}
    for line in text[4:end].splitlines():
        if ":" in line and not line.startswith((" ", "\t", "#")):
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip()
    return fm, text[end + 4:]


def is_non_node(fn):
    """Filenames excluded as corpus nodes: static non-nodes, templates, and
    examples (same skip convention as build_index.py)."""
    return fn in NON_NODES or fn.endswith("_template.md") or fn.endswith("_example.md")


def load_corpus(repo):
    """Returns (corpus, dup_findings). On a duplicate stem between memory/
    and memory/archive/, the active file wins (loaded first): the gate
    reports the duplicate, it does not die."""
    mem = os.path.join(repo, "memory")
    if not os.path.isdir(mem):
        fail(f"memory/ not found in {repo}")
    corpus, dups = {}, []
    for base, active in ((mem, True), (os.path.join(mem, "archive"), False)):
        if not os.path.isdir(base):
            continue
        for fn in sorted(os.listdir(base)):
            if not fn.endswith(".md") or (active and is_non_node(fn)):
                continue
            path = os.path.join(base, fn)
            if not os.path.isfile(path):
                continue
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            fm, body = split_frontmatter(text)
            if fn[:-3] in corpus:
                dups.append(finding("DUP-STEM", fn, "error", True,
                                    f"same stem in memory/ and memory/archive/: {fn} "
                                    f"(the active file wins; rename or remove the duplicate)"))
                continue
            corpus[fn[:-3]] = {
                "file": fn, "active": active, "fm": fm, "body": body,
                "rel": ("memory/" if active else "memory/archive/") + fn,
            }
    return corpus, dups


def check_untyped(corpus):
    out = []
    for s in sorted(corpus):
        n = corpus[s]
        if n["active"] and n["fm"].get("type") not in VALID_TYPES:
            out.append(finding("UNTYPED", n["file"], "warning", False,
                               f"{n['rel']}: type missing or invalid ({n['fm'].get('type')!r}), "
                               f"invisible to INDEX.generated.md, ORPHAN, and the sweep"))
    return out


def corpus_hash(repo):
    h = hashlib.sha256()
    for sub in ("memory", "scripts"):
        base = os.path.join(repo, sub)
        if not os.path.isdir(base):
            continue
        for root, dirs, files in os.walk(base):
            dirs.sort()
            for fn in sorted(files):
                if fn.endswith((".md", ".yml", ".txt")):
                    p = os.path.join(root, fn)
                    h.update(os.path.relpath(p, repo).encode() + b"\0")
                    with open(p, "rb") as fh:
                        h.update(fh.read())
                    h.update(b"\0")
    return h.hexdigest()[:16]


def is_node_type(corpus, stem):
    return corpus[stem]["fm"].get("type", "") in ("project", "strategic")


def check_broken(corpus):
    out = []
    for stem in sorted(corpus):
        n = corpus[stem]
        if not n["active"]:
            continue
        for target in WIKILINK.findall(n["body"]):
            if target not in corpus:
                out.append(finding("BROKEN", f"{n['file']}:{target}", "error", True,
                                   f"[[{target}]] in {n['rel']} does not resolve in memory/ or archive/"))
    return out


def graph(corpus):
    active = {s for s, n in corpus.items() if n["active"]}
    adj = {s: set() for s in active}
    incoming = {s: 0 for s in active}
    for s in sorted(active):
        for t in WIKILINK.findall(corpus[s]["body"]):
            if t in active and t != s:
                adj[s].add(t)
                adj[t].add(s)
                incoming[t] += 1
    comps, seen = [], set()
    for s in sorted(active):
        if s in seen:
            continue
        comp, stack = set(), [s]
        while stack:
            x = stack.pop()
            if x in comp:
                continue
            comp.add(x)
            seen.add(x)
            stack.extend(adj[x] - comp)
        comps.append(comp)
    return comps, incoming


def check_orphan_island(corpus, comps, incoming):
    out = []
    nucleus = max(comps, key=len) if comps else set()
    for s in sorted(incoming):
        if incoming[s] == 0 and is_node_type(corpus, s):
            out.append(finding("ORPHAN", corpus[s]["file"], "warning", False,
                               f"{corpus[s]['rel']}: no incoming wikilinks from active bodies"))
    for comp in comps:
        if comp is nucleus or len(comp) < 2:
            continue
        if any(is_node_type(corpus, s) for s in comp):
            key = ",".join(sorted(comp))
            out.append(finding("ISLAND", key, "info", False,
                               f"island disconnected from the nucleus ({len(comp)} nodes): {key}"))
    return out, nucleus


def check_index_rows(corpus, repo):
    out = []
    idx = os.path.join(repo, "memory", "MEMORY.md")
    if not os.path.isfile(idx):
        return [finding("INDEX-ROW", "MEMORY.md", "error", True, "MEMORY.md missing")]
    rows = {}
    with open(idx, encoding="utf-8") as fh:
        for line in fh:
            m = LINK_ROW.match(line.strip())
            if m:
                rows.setdefault(m.group(1), line.strip())
    on_disk = {("" if n["active"] else "archive/") + n["file"]: s
               for s, n in corpus.items()}
    for target in sorted(rows):
        base_fn = os.path.basename(target)
        if base_fn.endswith("_template.md") or base_fn.endswith("_example.md"):
            # Shipped *_template.md / *_example.md rows are by-design pointers
            # to files the gate does not load as nodes; never flag them, not
            # even after setup deletes the example.
            continue
        if target not in on_disk:
            out.append(finding("INDEX-ROW", target, "warning", False,
                               f"index row points to a nonexistent file: memory/{target}"))
            continue
        n = corpus[on_disk[target]]
        m_st = EMOJI.search(n["fm"].get("status", ""))
        m_row = EMOJI.search(rows[target])
        if m_st and m_row and m_st.group(0) != m_row.group(0):
            out.append(finding("INDEX-ROW", target, "warning", False,
                               f"row emoji ({m_row.group(0)}) != frontmatter status ({m_st.group(0)})"))
    for s in sorted(corpus):
        n = corpus[s]
        if n["active"] and n["file"] not in rows:
            out.append(finding("INDEX-ROW", n["file"], "warning", False,
                               f"active file with no row in MEMORY.md: {n['rel']}"))
    return out


def check_budget(repo):
    p = os.path.join(repo, "memory", "MEMORY.md")
    size = os.path.getsize(p) if os.path.isfile(p) else 0
    out = []
    if size > LIMIT_BYTES:
        out.append(finding("BUDGET", "MEMORY.md", "error", True,
                           f"MEMORY.md {size}B over the limit {LIMIT_BYTES}B: truncated at boot"))
    elif size > LIMIT_BYTES * BUDGET_WARN_RATIO:
        out.append(finding("BUDGET", "MEMORY.md", "warning", False,
                           f"MEMORY.md {size}B over 90% of the limit ({int(LIMIT_BYTES * BUDGET_WARN_RATIO)}B)"))
    return out, size


def check_stale_index(repo):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import build_index
    expected = build_index.render(repo)
    p = os.path.join(repo, "memory", "INDEX.generated.md")
    if not os.path.isfile(p):
        return [finding("STALE-INDEX", "INDEX.generated.md", "info", False,
                        "INDEX.generated.md missing (first generation pending)")]
    with open(p, encoding="utf-8") as fh:
        current = fh.read()
    if current != expected:
        return [finding("STALE-INDEX", "INDEX.generated.md", "warning", False,
                        "INDEX.generated.md is out of sync with the sources: regenerate "
                        "with: python3 scripts/build_index.py --write")]
    return []


def compute_delta(findings, size, baseline_path):
    with open(baseline_path, encoding="utf-8") as fh:
        raw = fh.read()
    base = json.loads(raw)
    old = {f["id"] for f in base.get("findings", [])}
    new = {f["id"] for f in findings}
    bsize = base.get("memory_md_bytes")
    return {
        "baseline_id": hashlib.sha256(raw.encode()).hexdigest()[:16],
        "baseline_created_at": base.get("created_at", "?"),
        "baseline_tree_hash": base.get("tree_hash", "?"),
        "new": sorted(new - old),
        "resolved": sorted(old - new),
        "budget_bytes_delta": (size - bsize) if (size is not None and bsize is not None) else None,
    }


def load_allowlist(repo):
    p = os.path.join(repo, "memory", "memory-gate-allowlist.yml")
    entries = []
    if not os.path.isfile(p):
        return entries
    cur = None
    with open(p, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line.strip() or line.strip().startswith("#"):
                continue
            if line.startswith("- "):
                cur = {}
                entries.append(cur)
                line = "  " + line[2:]
            if cur is not None and ":" in line:
                k, v = line.strip().split(":", 1)
                cur[k.strip()] = v.strip().strip('"')
    return entries


def entry_matches(e, f):
    """ISLAND matches by subset (entry nodes are a subset of the current
    island): an accepted island stays covered as it grows. Every other
    check matches on exact target."""
    if e.get("check", "") != f["check"]:
        return False
    if f["check"] == "ISLAND":
        enodes = {x for x in e.get("target", "").split(",") if x}
        fnodes = set(f["target"].split(","))
        return bool(enodes) and enodes <= fnodes
    return e.get("target", "") == f["target"]


def apply_allowlist(findings, entries):
    """Returns (keep, allowed, stale, invalid). Blocking findings are never
    silenced: the entry that matches one is reported in invalid_allowlist
    instead, and the finding stays in keep."""
    keep, allowed, invalid_idx = [], [], []
    matched = set()
    for f in findings:
        ms = [i for i, e in enumerate(entries) if entry_matches(e, f)]
        matched.update(ms)
        if ms and f["blocking"]:
            keep.append(f)
            invalid_idx += [i for i in ms if i not in invalid_idx]
        elif ms:
            allowed.append(f)
        else:
            keep.append(f)
    stale = [e for i, e in enumerate(entries) if i not in matched]
    invalid = [{"check": entries[i].get("check"), "target": entries[i].get("target")}
               for i in invalid_idx]
    return keep, allowed, stale, invalid


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", default=None)
    ap.add_argument("--as-of", dest="as_of", default=None)
    ap.add_argument("--only", default=None, help="comma-separated list of checks")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--baseline", default=None)
    args = ap.parse_args()

    repo = args.repo
    if not repo:
        r = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True)
        repo = r.stdout.strip()
    if not repo or not os.path.isdir(repo):
        fail("repo not determinable (use --repo)")
    as_of = parse_iso(args.as_of, "--as-of") if args.as_of else dt.date.today()
    checks = [c.strip().upper() for c in args.only.split(",")] if args.only else list(ALL_CHECKS)
    for c in checks:
        if c not in ALL_CHECKS:
            fail(f"unknown check: {c}")

    size = None
    try:
        corpus, dups = load_corpus(repo)
        comps, incoming = graph(corpus)
        findings = []
        if "DUP-STEM" in checks:
            findings += dups
        if "UNTYPED" in checks:
            findings += check_untyped(corpus)
        if "BROKEN" in checks:
            findings += check_broken(corpus)
        if "ORPHAN" in checks or "ISLAND" in checks:
            oi, nucleus = check_orphan_island(corpus, comps, incoming)
            findings += [f for f in oi if f["check"] in checks]
        else:
            nucleus = max(comps, key=len) if comps else set()
        if "INDEX-ROW" in checks:
            findings += check_index_rows(corpus, repo)
        if "BUDGET" in checks:
            b, size = check_budget(repo)
            findings += b
        if "STALE-INDEX" in checks:
            findings += check_stale_index(repo)
    except SystemExit:
        raise
    except Exception as e:
        fail(f"execution error: {e}")

    entries = load_allowlist(repo)
    findings, allowed, stale_allow, invalid_allow = apply_allowlist(findings, entries)

    out = {
        "created_at": dt.datetime.now().isoformat(timespec="seconds"),
        "as_of": as_of.isoformat(),
        "tree_hash": corpus_hash(repo),
        "checks_run": checks,
        "memory_md_bytes": size,
        "graph": {"components": len(comps), "nucleus_size": len(nucleus),
                  "no_incoming": sorted(s for s in incoming if incoming[s] == 0)},
        "findings": findings,
        "allowlisted": sorted(f["id"] for f in allowed),
        "stale_allowlist": [{"check": e.get("check"), "target": e.get("target")} for e in stale_allow],
        "invalid_allowlist": invalid_allow,
        "green": not findings,
    }
    if args.baseline:
        try:
            delta = compute_delta(findings, size, args.baseline)
        except Exception as e:
            fail(f"baseline unreadable: {e}")
        out["delta"] = delta
    print(json.dumps(out, ensure_ascii=False, indent=1))
    sys.exit(1 if args.strict and any(f["blocking"] for f in findings) else 0)


if __name__ == "__main__":
    main()
