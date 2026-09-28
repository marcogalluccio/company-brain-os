#!/usr/bin/env python3
"""Company Brain OS CLAUDE.md scanner: read-only drift check.

Finds claims in CLAUDE.md files that no longer match the repository:
  DEAD   a file named in a fenced folder tree that does not exist under that folder
  SKILL  a `skills/<name>` citation with no skills/<name>/SKILL.md behind it
  PATH   a `../` cross-folder reference that does not resolve
  SCOPE  a scope tag in the root Structure section that disagrees with
         .github/CODEOWNERS (only when that file exists)

Read-only: never edits a file. Prints a JSON list of findings to stdout and a
one-line summary to stderr.

Usage:
  python3 scripts/check_claudemd.py [--root <repo>] [--strict]

Exit: 0 = scan completed; 1 = --strict and at least one "error" finding;
2 = execution error.

Finding schema:
  {"file": "<repo-relative CLAUDE.md>", "check": "DEAD"|"SKILL"|"PATH"|"SCOPE",
   "severity": "error"|"info", "claim": "<what the file says>",
   "reality": "<what the repository holds>"}

Scope tags: a bullet of the root CLAUDE.md Structure section may carry
`(scope: shared)` or `(scope: <operator-slug>)`. `shared` expects two or more
CODEOWNERS logins on that path; a slug expects exactly one login, the `github`
value of operators/<slug>.md. Untagged bullets are never checked, so a team
that does not use tags gets no SCOPE finding.

Deliberately conservative: plain inline file names are not resolved (prose
is full of examples and patterns), only the two unambiguous inline signals
(skill citations and `../` paths) and the leaves of an explicit folder tree.
"""
import argparse
import json
import os
import re
import subprocess
import sys

SKIP_DIRS = {".git", ".claude", "node_modules", "dist", "build", "venv", "__pycache__"}
REF_EXT = {".md", ".html", ".py", ".json", ".css", ".js", ".ts", ".sh",
           ".csv", ".txt", ".yml", ".yaml"}
PLACEHOLDER_RE = re.compile(r"[\[\]<>{}*]|\.\.\.|YYYY|://")
TREE_LEAF_RE = re.compile(r"[│├└]\s*[├└]?──\s*([^\s←<#]+)")
BACKTICK_RE = re.compile(r"`([^`]+)`")
# Fenced blocks are removed before inline scanning: a ``` fence has an odd
# backtick count and would shift every inline token after it by one.
FENCE_RE = re.compile(r"```.*?```", re.S)
STRUCTURE_BULLET_RE = re.compile(r"^-\s+`([^`]+?)/?`")
SCOPE_TAG_RE = re.compile(r"\(scope:\s*([a-z0-9-]+)\)")
FRONTMATTER_KEY_RE = re.compile(r"^([A-Za-z_]+):\s*(.*)$")
REGISTRY_NON_FILES = {"CLAUDE.md", "ONBOARDING.md", "operator_template.md"}


def repo_root():
    out = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True, check=True)
    return out.stdout.strip()


def finding(file, check, severity, claim, reality):
    return {"file": file, "check": check, "severity": severity,
            "claim": claim, "reality": reality}


def find_claudemds(root):
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        if "CLAUDE.md" in filenames:
            found.append(os.path.join(dirpath, "CLAUDE.md"))
    return sorted(found)


def real_skills(root):
    """Repo-relative paths of every folder holding a SKILL.md."""
    skills = set()
    sk_root = os.path.join(root, "skills")
    for dirpath, dirnames, filenames in os.walk(sk_root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        if "SKILL.md" in filenames:
            skills.add(os.path.relpath(dirpath, root))
    return skills


def looks_like_ref(tok):
    tok = tok.strip()
    if not tok or PLACEHOLDER_RE.search(tok):
        return False
    if tok.startswith(("http", "@", "#", "$", "/")):
        return False
    _, ext = os.path.splitext(tok)
    return ("/" in tok) or (ext.lower() in REF_EXT)


def resolves(ref, claude_dir, root):
    ref = ref.rstrip("/")
    return any(os.path.exists(os.path.join(base, ref)) for base in (claude_dir, root))


def basename_exists_under(name, claude_dir):
    target = name.rstrip("/")
    for dirpath, dirnames, filenames in os.walk(claude_dir):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        if target in filenames or target in dirnames:
            return True
    return False


def check_file(path, root, skills):
    rel = os.path.relpath(path, root)
    claude_dir = os.path.dirname(path)
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    out = []

    seen = set()
    for tok in BACKTICK_RE.findall(FENCE_RE.sub("", text)):
        tok = tok.strip()
        if tok in seen or not looks_like_ref(tok):
            continue
        seen.add(tok)
        norm = tok.rstrip("/")
        if norm.startswith("skills/"):
            if norm not in skills and not resolves(tok, claude_dir, root):
                out.append(finding(rel, "SKILL", "error", f"cites `{tok}`",
                                   "no such skill folder with a SKILL.md"))
        elif tok.startswith("../") and not resolves(tok, claude_dir, root):
            out.append(finding(rel, "PATH", "error", f"cross-folder ref `{tok}`",
                               "does not resolve from this folder"))

    seen_leaf = set()
    for m in TREE_LEAF_RE.finditer(text):
        leaf = m.group(1).strip().rstrip("/,")
        if leaf in seen_leaf or PLACEHOLDER_RE.search(leaf):
            continue
        seen_leaf.add(leaf)
        _, ext = os.path.splitext(leaf)
        if ext.lower() not in REF_EXT:
            continue
        if not basename_exists_under(leaf, claude_dir):
            out.append(finding(rel, "DEAD", "error", f"tree lists `{leaf}`",
                               "no file with that name under this folder"))
    return out


def frontmatter(path):
    out = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    if not lines or lines[0].strip() != "---":
        return out
    for line in lines[1:]:
        if line.strip() == "---":
            break
        m = FRONTMATTER_KEY_RE.match(line)
        if m:
            out[m.group(1)] = m.group(2).strip()
    return out


def normalise_login(value):
    return value.strip().lstrip("@").lower()


def registry_logins(root):
    """{github login (lower) : slug} from operators/*.md, template excluded."""
    logins = {}
    reg = os.path.join(root, "operators")
    if not os.path.isdir(reg):
        return logins
    for name in sorted(os.listdir(reg)):
        if not name.endswith(".md") or name in REGISTRY_NON_FILES:
            continue
        login = normalise_login(frontmatter(os.path.join(reg, name)).get("github", ""))
        if login:
            logins[login] = name[:-3]
    return logins


def codeowners(root):
    """{path without slashes : [logins]} or None when the file is absent.
    Lines with wildcards are skipped: the tag convention names plain folders."""
    path = os.path.join(root, ".github", "CODEOWNERS")
    if not os.path.exists(path):
        return None
    owners = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 2 or "*" in parts[0]:
                continue
            owners[parts[0].strip("/")] = [normalise_login(p) for p in parts[1:] if p.startswith("@")]
    return owners


def check_scope(root):
    out = []
    owners = codeowners(root)
    root_claude = os.path.join(root, "CLAUDE.md")
    if owners is None or not os.path.exists(root_claude):
        return out
    logins = registry_logins(root)
    in_structure = False
    with open(root_claude, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith("## "):
                in_structure = line.strip() == "## Structure"
                continue
            if not in_structure:
                continue
            mb = STRUCTURE_BULLET_RE.match(line)
            mt = SCOPE_TAG_RE.search(line)
            if not (mb and mt):
                continue
            folder = mb.group(1).strip("/")
            tag = mt.group(1)
            claim = f"`{folder}` tagged (scope: {tag})"
            actual = owners.get(folder)
            if actual is None:
                out.append(finding("CLAUDE.md", "SCOPE", "info", claim,
                                   "no CODEOWNERS line for that path"))
                continue
            listed = ", ".join("@" + a for a in actual) or "nobody"
            if tag == "shared":
                if len(actual) < 2:
                    out.append(finding("CLAUDE.md", "SCOPE", "error", claim,
                                       f"CODEOWNERS lists {listed}: shared expects two or more"))
            else:
                expected = [login for login, slug in logins.items() if slug == tag]
                if not expected:
                    out.append(finding("CLAUDE.md", "SCOPE", "error", claim,
                                       f"no operators/{tag}.md with a github value"))
                elif actual != expected:
                    out.append(finding("CLAUDE.md", "SCOPE", "error", claim,
                                       f"CODEOWNERS lists {listed}; expected exactly @{expected[0]}"))
    return out


def scan(root):
    skills = real_skills(root)
    findings = []
    for path in find_claudemds(root):
        findings.extend(check_file(path, root, skills))
    findings.extend(check_scope(root))
    return findings


def main():
    ap = argparse.ArgumentParser(description="Read-only drift scan of CLAUDE.md files.")
    ap.add_argument("--root", help="repository root (default: git rev-parse --show-toplevel)")
    ap.add_argument("--strict", action="store_true", help="exit 1 if any error-severity finding")
    args = ap.parse_args()
    try:
        root = os.path.abspath(args.root) if args.root else repo_root()
        if not os.path.isdir(root):
            print(f"check_claudemd: root is not a directory: {root}", file=sys.stderr)
            sys.exit(2)
        findings = scan(root)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"check_claudemd: {exc}", file=sys.stderr)
        sys.exit(2)
    counts = {}
    for f in findings:
        counts[f["check"]] = counts.get(f["check"], 0) + 1
    summary = ", ".join(f"{k}={v}" for k, v in sorted(counts.items())) or "none"
    files = len({f["file"] for f in findings})
    print(f"check_claudemd: {len(findings)} finding(s) in {files} file(s) ({summary})", file=sys.stderr)
    json.dump(findings, sys.stdout, ensure_ascii=False, indent=2)
    print()
    if args.strict and any(f["severity"] == "error" for f in findings):
        sys.exit(1)


if __name__ == "__main__":
    main()
