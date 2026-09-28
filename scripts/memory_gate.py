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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_index  # memory_roots, is_primary, PRIMARY, render

LIMIT_BYTES = int(os.environ.get("MEMORY_GATE_LIMIT_BYTES", "24986"))  # host tool's auto-load cap
BUDGET_WARN_RATIO = 0.90
# Area indexes are opened on demand, not at session start, but an index heavier
# than what the boot tolerates is too heavy to open at all. Default: same cap.
AREA_LIMIT_BYTES = int(os.environ.get("MEMORY_GATE_AREA_LIMIT_BYTES", str(LIMIT_BYTES)))
# Per-row budget for an index file: what is left of the auto-load cap once the
# fixed prose (headings, intro sentences) is subtracted, divided among the rows
# plus headroom for growth. The headroom is a declared allowance, not a
# measurement: an index is expected to gain about a quarter more rows before
# anyone prunes it. MEMORY_GATE_ROW_LIMIT_BYTES replaces the derivation with a
# fixed cap (tests, or a team that prefers a number).
ROW_BUDGET_HEADROOM = 0.25
ROW_LIMIT_BYTES = os.environ.get("MEMORY_GATE_ROW_LIMIT_BYTES")
ROW_BUDGET_WORST = 5  # how many of the heaviest rows to name in the finding
NON_NODES = {"MEMORY.md", "REFERENCES.md", "CLAUDE.md", "INDEX.generated.md"}
EXEMPT_TYPES = {"reference", "feedback"}
ALL_CHECKS = ["BROKEN", "ORPHAN", "ISLAND", "INDEX-ROW", "BUDGET", "ROW-BUDGET",
              "STALE-INDEX", "DUP-STEM", "DUP-ROOT", "UNTYPED"]
VALID_TYPES = {"project", "strategic", "reference", "feedback"}
WIKILINK = re.compile(r"\[\[([A-Za-z0-9_\-]+)\]\]")
EMOJI = re.compile("[\U0001F534\U0001F7E0\U0001F7E1\U0001F7E2\U0001F535❌]")
LINK_ROW = re.compile(r"^- \[[^\]]+\]\(((?:archive/)?[A-Za-z0-9_\-]+\.md)\)")
# Pointer row of the primary index's `## Areas` section:
# - [Name](../areas/<name>/memory/MEMORY.md) - what it holds, when to open it
AREA_ROW = re.compile(r"^- \[[^\]]+\]\(\.\./(areas/[A-Za-z0-9_\-]+/memory)/MEMORY\.md\)")


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
    """Returns (corpus, dup_findings). Nodes are the union of every memory
    root. A duplicate stem inside one root (active vs archive) is DUP-STEM
    and the active file wins; the same stem in two roots is DUP-ROOT and the
    root loaded first (the primary) wins. Either way the gate reports and
    goes on; it does not die on a duplicate."""
    roots = build_index.memory_roots(repo)
    if not roots:
        fail(f"memory/ not found in {repo}")
    corpus, dups = {}, []
    for root in roots:
        rroot = os.path.relpath(root, repo)
        for base, active in ((root, True), (os.path.join(root, "archive"), False)):
            if not os.path.isdir(base):
                continue
            for fn in sorted(os.listdir(base)):
                if not fn.endswith(".md") or (active and is_non_node(fn)):
                    continue
                if not active and fn == "INDEX.md":  # the archive's own index, not a node
                    continue
                path = os.path.join(base, fn)
                if not os.path.isfile(path):
                    continue
                with open(path, encoding="utf-8") as fh:
                    text = fh.read()
                fm, body = split_frontmatter(text)
                rel = f"{rroot}/{fn}" if active else f"{rroot}/archive/{fn}"
                stem = fn[:-3]
                if stem in corpus:
                    prev = corpus[stem]
                    if prev["root"] == rroot:
                        dups.append(finding("DUP-STEM", fn, "error", True,
                                            f"same stem in {rroot}/ and {rroot}/archive/: {fn} "
                                            f"(the active file wins; rename or remove the duplicate)"))
                    else:
                        dups.append(finding("DUP-ROOT", fn, "error", True,
                                            f"same stem in two memory roots: {prev['rel']} and {rel} "
                                            f"(an item has one home, the root that owns its next "
                                            f"action; move or archive the other copy)"))
                    continue
                corpus[stem] = {"file": fn, "active": active, "fm": fm, "body": body,
                                "rel": rel, "root": rroot}
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
    subs = [os.path.relpath(r, repo) for r in build_index.memory_roots(repo)] + ["scripts"]
    for sub in subs:
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
                                   f"[[{target}]] in {n['rel']} does not resolve in any memory root (active or archive)"))
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


def index_rows(root):
    """Index target -> row text, from every file that may carry index rows.

    MEMORY.md and REFERENCES.md rows point at `file.md` (or, in the inline
    layout, `archive/file.md`); archive/INDEX.md rows point at `file.md`
    relative to the archive folder and are keyed as `archive/file.md`, so a
    row is the same target wherever it lives.
    """
    rows = {}
    for src, prefix in (("MEMORY.md", ""), ("REFERENCES.md", ""),
                        (os.path.join("archive", "INDEX.md"), "archive/")):
        p = os.path.join(root, src)
        if not os.path.isfile(p):
            continue
        with open(p, encoding="utf-8") as fh:
            for line in fh:
                m = LINK_ROW.match(line.strip())
                if m:
                    target = m.group(1)
                    if prefix and not target.startswith(prefix):
                        target = prefix + target
                    rows.setdefault(target, line.strip())
    return rows


def index_target(repo, root):
    """Finding target for an index file: `MEMORY.md` for the primary (stable
    for allowlists written before federation), `<root>/MEMORY.md` for an area."""
    return "MEMORY.md" if build_index.is_primary(repo, root) else f"{os.path.relpath(root, repo)}/MEMORY.md"


def node_target(repo, root, name):
    """Finding target for an individual memory file: `name` bare for the
    primary (stable for allowlists written before federation), `<root>/name`
    for an area. Same rule as index_target(), applied per-node so that two
    roots never produce the same finding id for two different files."""
    return name if build_index.is_primary(repo, root) else f"{os.path.relpath(root, repo)}/{name}"


def check_index_rows(corpus, repo):
    out = []
    roots = build_index.memory_roots(repo)
    for root in roots:
        rroot = os.path.relpath(root, repo)
        tgt = index_target(repo, root)
        if not os.path.isfile(os.path.join(root, "MEMORY.md")):
            out.append(finding("INDEX-ROW", tgt, "error", True, f"{rroot}/MEMORY.md missing"))
            continue
        rows = index_rows(root)
        on_disk = {("" if n["active"] else "archive/") + n["file"]: s
                   for s, n in corpus.items() if n["root"] == rroot}
        for target in sorted(rows):
            base_fn = os.path.basename(target)
            if base_fn.endswith("_template.md") or base_fn.endswith("_example.md"):
                # Shipped *_template.md / *_example.md rows are by-design pointers
                # to files the gate does not load as nodes; never flag them, not
                # even after setup deletes the example.
                continue
            if target not in on_disk:
                stem = base_fn[:-3] if base_fn.endswith(".md") else base_fn
                elsewhere = corpus.get(stem)
                if elsewhere and elsewhere["root"] != rroot:
                    # The stem exists, just not in this root's corpus: the row
                    # is misfiled, not dangling. Say so, rather than claiming a
                    # file that is sitting right there does not exist.
                    detail = (f"index row points to a file that lives in another "
                              f"root ({elsewhere['rel']}), not {rroot}/{target}")
                else:
                    detail = f"index row points to a nonexistent file: {rroot}/{target}"
                out.append(finding("INDEX-ROW", node_target(repo, root, target), "warning", False, detail))
                continue
            n = corpus[on_disk[target]]
            m_st = EMOJI.search(n["fm"].get("status", ""))
            m_row = EMOJI.search(rows[target])
            if m_st and m_row and m_st.group(0) != m_row.group(0):
                out.append(finding("INDEX-ROW", node_target(repo, root, target), "warning", False,
                                   f"row emoji ({m_row.group(0)}) != frontmatter status "
                                   f"({m_st.group(0)}) in {rroot}/"))
        for s in sorted(corpus):
            n = corpus[s]
            if n["root"] == rroot and n["active"] and n["file"] not in rows:
                out.append(finding("INDEX-ROW", node_target(repo, root, n["file"]), "warning", False,
                                   f"active file with no index row in {rroot}/: {n['rel']}"))
    # The primary index's `## Areas` pointer rows and the area roots on disk must agree.
    primary_idx = os.path.join(repo, build_index.PRIMARY, "MEMORY.md")
    if os.path.isfile(primary_idx):
        pointed = set()
        with open(primary_idx, encoding="utf-8") as fh:
            for line in fh:
                m = AREA_ROW.match(line.strip())
                if m:
                    pointed.add(m.group(1))
        areas = {os.path.relpath(r, repo) for r in roots if not build_index.is_primary(repo, r)}
        for a in sorted(areas - pointed):
            out.append(finding("INDEX-ROW", f"{a}/MEMORY.md", "warning", False,
                               f"area root with no pointer row under ## Areas in memory/MEMORY.md: {a}/"))
        for p in sorted(pointed - areas):
            out.append(finding("INDEX-ROW", f"{p}/MEMORY.md", "warning", False,
                               f"## Areas row in memory/MEMORY.md points to a missing index: {p}/MEMORY.md"))
    return out


def check_budget(repo):
    """Returns (findings, sizes) with sizes = {index target: bytes}, one cap per index."""
    out, sizes = [], {}
    for root in build_index.memory_roots(repo):
        p = os.path.join(root, "MEMORY.md")
        size = os.path.getsize(p) if os.path.isfile(p) else 0
        tgt = index_target(repo, root)
        primary = build_index.is_primary(repo, root)
        limit = LIMIT_BYTES if primary else AREA_LIMIT_BYTES
        sizes[tgt] = size
        if size > limit:
            why = "truncated at boot" if primary else "too heavy to open on demand"
            out.append(finding("BUDGET", tgt, "error", True,
                               f"{tgt} {size}B over the limit {limit}B: {why}"))
        elif size > limit * BUDGET_WARN_RATIO:
            out.append(finding("BUDGET", tgt, "warning", False,
                               f"{tgt} {size}B over 90% of the limit ({int(limit * BUDGET_WARN_RATIO)}B)"))
    return out, sizes


def row_budget(limit, file_bytes, rows):
    """Bytes one index row may take: (cap - fixed prose) / (rows * (1 + headroom)).
    Pure in its three arguments only, so a caller iterating over several roots
    (or an env override) can reuse it unchanged for each one."""
    prose = file_bytes - sum(n for n, _ in rows)
    return int((limit - prose) / (len(rows) * (1 + ROW_BUDGET_HEADROOM)))


def index_row_sizes(path):
    """[(byte length, target)] for every index row in the file."""
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            m = LINK_ROW.match(line.strip())
            if m:
                rows.append((len(line.encode("utf-8")), m.group(1)))
    return rows


def check_row_budget(repo):
    """MEMORY.md only, not REFERENCES.md or archive/INDEX.md: the budget is
    derived from LIMIT_BYTES, the host tool's auto-load truncation cap, which
    applies to the one file the host auto-loads. The sibling index files are
    read on demand and carry no such cap, so there is no limit to derive a
    per-row share from. One aggregated warning per run: how many rows exceed
    the per-row budget, the total excess, and the heaviest rows as a concrete
    target. Aggregated on purpose: near the cap roughly half the rows exceed
    the average, and one finding per row would be unusable noise."""
    out = []
    for root in build_index.memory_roots(repo):
        p = os.path.join(root, "MEMORY.md")
        if not os.path.isfile(p):
            continue
        tgt = index_target(repo, root)
        limit = LIMIT_BYTES if build_index.is_primary(repo, root) else AREA_LIMIT_BYTES
        rows = index_row_sizes(p)
        if not rows:
            continue
        budget = int(ROW_LIMIT_BYTES) if ROW_LIMIT_BYTES else row_budget(limit, os.path.getsize(p), rows)
        over = sorted((r for r in rows if r[0] > budget), reverse=True)
        if not over:
            continue
        excess = sum(n - budget for n, _ in over)
        worst = ", ".join(f"{t} ({n}B)" for n, t in over[:ROW_BUDGET_WORST])
        out.append(finding("ROW-BUDGET", tgt, "warning", False,
                           f"{len(over)}/{len(rows)} index rows above the per-row budget of "
                           f"{budget}B (excess {excess}B). Heaviest: {worst}. Collapse the "
                           f"previous state into the new line instead of appending to it."))
    return out


def check_stale_index(repo):
    out = []
    for root in build_index.memory_roots(repo):
        rroot = os.path.relpath(root, repo)
        tgt = "INDEX.generated.md" if build_index.is_primary(repo, root) else f"{rroot}/INDEX.generated.md"
        expected = build_index.render(repo, root)
        p = os.path.join(root, "INDEX.generated.md")
        if not os.path.isfile(p):
            out.append(finding("STALE-INDEX", tgt, "info", False,
                               f"{rroot}/INDEX.generated.md missing (first generation pending)"))
            continue
        with open(p, encoding="utf-8") as fh:
            current = fh.read()
        if current != expected:
            out.append(finding("STALE-INDEX", tgt, "warning", False,
                               f"{rroot}/INDEX.generated.md is out of sync with the sources: "
                               "regenerate with: python3 scripts/build_index.py --write"))
    return out


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

    size, sizes = None, {}
    try:
        corpus, dups = load_corpus(repo)
        comps, incoming = graph(corpus)
        findings = []
        if "DUP-STEM" in checks or "DUP-ROOT" in checks:
            findings += [f for f in dups if f["check"] in checks]
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
            b, sizes = check_budget(repo)
            size = sizes.get("MEMORY.md")
            findings += b
        if "ROW-BUDGET" in checks:
            findings += check_row_budget(repo)
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
        "index_bytes": sizes,
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
