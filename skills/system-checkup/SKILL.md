---
name: system-checkup
description: |
  Weekly whole-workspace health check: registry, structure, skills, and a
  memory summary, plus, where docs/GOVERNANCE.md is adopted, the git layer.
  Every check that needs a tool this machine does not have is skipped and
  reported as skipped, never silently. Steps 1-5 run standalone, plus the
  local half of Step 6; the GitHub half of Step 6 is inert without an
  authenticated gh CLI and an activated docs/GOVERNANCE.md.
  Use when the operator says: system checkup, /system-checkup, system check,
  weekly review, is everything in order.
---

# System checkup

A full pass over the workspace: registry integrity, folder structure, skill
hygiene, a memory summary, and, if the team turned on `docs/GOVERNANCE.md`,
the git layer. Run it weekly, or any time the system feels out of sync. It
degrades gracefully: a missing tool never breaks the run, it just narrows
what this pass can see, and the final report says exactly what was skipped
and why.

Run the steps in order. Nothing gets changed without the operator's approval.

---

## Step 0: Resolve the operator, then probe capabilities

Every downstream step needs to know who is running the session, and this
step also decides up front which of the later checks this machine can even
attempt, so the report can say "skipped" instead of failing partway through.

```bash
cd "$(git rev-parse --show-toplevel)"
GIT_NAME="$(git config user.name)"
if [ -z "$GIT_NAME" ]; then
  echo "IDENTITY ERROR: git config user.name is empty. Set it as described in operators/ONBOARDING.md Step 4."
  exit 1
fi
MATCHES=""
for f in operators/*.md; do
  case "$f" in
    operators/CLAUDE.md|operators/ONBOARDING.md|operators/operator_template.md) continue ;;
  esac
  if awk '/^---$/{if(f)exit;f=1;next} f' "$f" | sed 's/^[[:space:]]*//' | grep -qxF -- "- $GIT_NAME"; then
    MATCHES="$MATCHES $f"
  fi
done
N=$(echo $MATCHES | wc -w | tr -d ' ')
if [ "$N" != "1" ]; then
  echo "IDENTITY ERROR: git user.name \"$GIT_NAME\" matches $N operator files:$MATCHES"
  echo "Exactly one operators/<slug>.md must claim this value in git_names."
  echo "Fix your identity or the registry (see operators/CLAUDE.md), then rerun."
  exit 1
fi
SLUG="$(basename $MATCHES .md)"
TODAY="$(date +%Y-%m-%d)"
echo "operator=$SLUG today=$TODAY"
```

On `IDENTITY ERROR`, stop the skill and show the message to the operator as
it came out. Do not continue with a guessed slug, and do not invent one from
the git name. The registry rule in `operators/CLAUDE.md` is binding: resolve
the active operator by matching `git config user.name` against every
registry file's `git_names`; exactly one match proceeds, zero or multiple
matches stop.

Now probe what this machine can do. Every later step that needs one of these
tools checks the corresponding variable before running, and reports a named
skip instead of failing if it is `0`:

```bash
command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && GH_OK=1 || GH_OK=0
command -v python3 >/dev/null 2>&1 && PY_OK=1 || PY_OK=0
git remote get-url origin >/dev/null 2>&1 && REMOTE_OK=1 || REMOTE_OK=0
echo "gh=$GH_OK python3=$PY_OK remote=$REMOTE_OK"
```

Where each miss routes:

- `GH_OK=0`: the GitHub half of Step 6 skips with "skipped: gh not
  authenticated"; its local half (the governance coherence check) still runs.
  No other step needs `gh`.
- `PY_OK=0`: Step 3 skips the `CLAUDE.md` scanner with "skipped: python3 not
  available", and Step 5 (memory summary) cannot run `scripts/memory_gate.py`
  even if the team adopted `docs/ADVANCED.md`; it falls back to the inline
  checks from `/memory-checkup` Step 1, which are plain shell and need no
  Python.
- `REMOTE_OK=0`: Step 6 skips with "skipped: no origin remote configured",
  since a `gh api repos/{owner}/{repo}/...` call has nothing to resolve
  `{owner}/{repo}` against without one. This is the normal state of a brand
  new brain that has not finished `SETUP.md` yet.

Record every skip as you go; Step 7 closes with the full list.

---

## Step 1: Security scan (always first)

Before reading anything else, scan the daily logs touched in the last 7 days
for exposed credentials. The time window comes from git's own history, not
shell date arithmetic, so it is portable and correct regardless of the local
`date` implementation:

```bash
cd "$(git rev-parse --show-toplevel)"
LOGS="$(git log --since="7 days ago" --name-only --pretty=format: -- daily-log/ 2>/dev/null | sort -u)"
if [ -n "$LOGS" ]; then
  echo "$LOGS" | while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    grep -nEi 're_[A-Za-z0-9]|sk_[A-Za-z0-9]|pk_[A-Za-z0-9]|Bearer [A-Za-z0-9]|api[_-]key|(key|token|password|secret)[[:space:]]*:[[:space:]]*[A-Za-z0-9_-]{16,}|rotate|revoke' "$f" \
      | sed "s|^|$f: |"
  done
fi
```

Any hit here, an API key pattern, a pasted token, or a note that says
"rotate" or "revoke" a credential, is the first finding regardless of
everything else this checkup turns up.

---

## Step 2: Registry sanity

Two independent problems, both mechanical: two operator files claiming the
same identity, and a daily log whose filename slug does not exist in the
registry.

```bash
cd "$(git rev-parse --show-toplevel)"
REG_TMP="${TMPDIR:-/tmp}/checkup-registry.$$"
# duplicate slugs across operator files
for f in operators/*.md; do
  case "$f" in operators/CLAUDE.md|operators/ONBOARDING.md|operators/operator_template.md) continue ;; esac
  awk '/^---$/{if(x)exit;x=1;next} x' "$f" | grep '^slug:' | sed "s|^|$f: |"
done | sort > "$REG_TMP"
cut -d: -f3- "$REG_TMP" | sort | uniq -d | while IFS= read -r dup; do
  while IFS= read -r line; do
    case "$line" in *":$dup") echo "DUPLICATE SLUG: $line" ;; esac
  done < "$REG_TMP"
done
# duplicate git_names entries across operator files
for f in operators/*.md; do
  case "$f" in operators/CLAUDE.md|operators/ONBOARDING.md|operators/operator_template.md) continue ;; esac
  awk '/^---$/{if(f2)exit;f2=1;next} f2' "$f" | sed 's/^[[:space:]]*//' | grep '^- ' | sed "s|^|$f: |"
done | sort > "$REG_TMP"
cut -d: -f2- "$REG_TMP" | sort | uniq -d | while IFS= read -r dup; do
  while IFS= read -r line; do
    case "$line" in *":$dup") echo "DUPLICATE git_names ENTRY: $line" ;; esac
  done < "$REG_TMP"
done
rm -f "$REG_TMP"
# daily-log lineage: every log filename slug must exist in the registry
find daily-log -maxdepth 1 -name '*.md' 2>/dev/null | while IFS= read -r f; do
  base=$(basename "$f" .md)
  case "$base" in CLAUDE) continue ;; esac
  slugpart="${base#????-??-??-}"
  [ -f "operators/$slugpart.md" ] || echo "ORPHAN LOG LINEAGE: $f (slug '$slugpart' not in the registry)"
done
```

The `operators/*.md` glob is safe to leave bare here: `operators/CLAUDE.md`,
`ONBOARDING.md`, and `operator_template.md` always exist in a shipped brain,
so the glob always has at least one match. `daily-log/*.md` has no such
guarantee, a fresh brain's `daily-log/` can be empty, and an unguarded glob
with zero matches is fatal in zsh (not just silently empty, as in bash), so
the lineage check is `find`-based instead, matching the pattern already used
in `/memory-checkup` Step 1.

---

## Step 3: Structure

Compare what is on disk against what the root `CLAUDE.md` Structure section
documents, and check the shape every `areas/<name>/` folder is supposed to
have.

```bash
cd "$(git rev-parse --show-toplevel)"
DISK_TOP="$(find . -maxdepth 1 -type d ! -name '.' ! -name '.*' | sed 's|^\./||' | sed 's|$|/|' | sort)"
DOC_TOP="$(awk '/^## Structure/{f=1;next} /^## /{f=0} f' CLAUDE.md | grep -oE '`[A-Za-z0-9_.-]+/' | tr -d '`' | sort -u)"
comm -23 <(echo "$DISK_TOP") <(echo "$DOC_TOP")
find areas -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while IFS= read -r d; do
  [ -f "$d/CLAUDE.md" ] || echo "MISSING CLAUDE.md: $d"
  [ -f "$d/Context.md" ] || echo "MISSING Context.md: $d"
done
find . -maxdepth 1 -type f ! -name '.*' | sed 's|^\./||' | sort
```

`DISK_TOP` excludes every dot-prefixed entry (`.git`, `.claude`, and any
tool-infrastructure directory a machine happens to have), not just a
hardcoded pair, since the root `CLAUDE.md` Structure section only documents
visible content folders. Both sides of the `comm` get a trailing `/` so a
plain directory name and its `` `name/` `` backtick form in the doc actually
compare equal instead of always mismatching. The first block's output is
top-level folders that exist on disk but are not named in the Structure
section: propose the one-line addition for each. The `areas/` loop flags any
area missing its `CLAUDE.md` or `Context.md`. The last `find` lists loose
files sitting at the repo root; judge each one on whether it belongs inside
an area instead of leaving it there.

Then the drift scanner, which reads every `CLAUDE.md` for claims the repo no longer
backs:

```bash
cd "$(git rev-parse --show-toplevel)"
if [ "$PY_OK" = 1 ] && [ -f scripts/check_claudemd.py ]; then
  python3 scripts/check_claudemd.py
else
  echo "skipped: CLAUDE.md scanner (python3 not available or scripts/check_claudemd.py absent)"
fi
```

It prints a JSON list: `DEAD` (a file named in a folder tree that does not exist),
`SKILL` (a `skills/<name>` citation with nothing behind it), `PATH` (a `../`
reference that does not resolve), and, only when `.github/CODEOWNERS` exists, `SCOPE`
(a `(scope: shared)` or `(scope: <slug>)` tag on a root Structure bullet that
disagrees with the CODEOWNERS routing, the slug resolved through `operators/`). Every
`error` is a finding to propose a fix for; an `info` is worth a sentence. An empty
list is the normal state and is reported as such. The scanner never edits anything,
and neither does this step: a `CLAUDE.md` fix is proposed under Step 7's separate
approval.

---

## Step 4: Skills

Check the registration link, then the shape of every skill folder.

```bash
cd "$(git rev-parse --show-toplevel)"
if [ -e ".claude/skills" ] || [ -L ".claude/skills" ]; then
  ls .claude/skills/ >/dev/null 2>&1 && echo "Skill registration: ok." \
    || echo "Skill link broken: recreate it (SETUP.md Step 4)."
else
  echo "Skills are not registered on this machine yet."
  echo "Run once: mkdir -p .claude && ln -s ../skills .claude/skills"
fi
find skills -mindepth 1 -maxdepth 1 -type d ! -name '_improvements' 2>/dev/null | while IFS= read -r d; do
  name=$(basename "$d")
  if [ ! -f "$d/SKILL.md" ]; then
    echo "MISSING SKILL.md: $d"
    continue
  fi
  fm_name=$(awk '/^---$/{if(x)exit;x=1;next} x && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$d/SKILL.md")
  [ "$fm_name" = "$name" ] || echo "NAME MISMATCH: $d/SKILL.md declares name '$fm_name', folder is '$name'"
  grep -q '^## Self-improvement$' "$d/SKILL.md" || echo "MISSING FOOTER: $d/SKILL.md has no Self-improvement section"
done
```

The registration check is the same detect-only semantics as `/sync` Step 2,
on purpose: it tests both `-e` and `-L` so a dangling symlink is reported as
"broken" rather than "not registered", and it never creates the link itself,
the operator runs the one-liner.

---

## Step 5: Memory summary

```bash
cd "$(git rev-parse --show-toplevel)"
ADOPTED=0
if find memory areas/*/memory -maxdepth 1 \( -name 'project_*.md' -o -name 'strategic_*.md' \) 2>/dev/null \
     | xargs -I{} grep -l '^salience:' {} 2>/dev/null | grep -q .; then
  ADOPTED=1
fi
if [ "$PY_OK" = 1 ] && [ -f scripts/memory_gate.py ] && [ "$ADOPTED" = 1 ]; then
  python3 scripts/memory_gate.py
  [ -f scripts/salience_sweep.py ] && python3 scripts/salience_sweep.py | python3 -c '
import json, sys
d = json.load(sys.stdin)
restamps, cold, errors = len(d["restamps"]), len(d["emoji_suggestions"]), len(d["errors"])
print(f"salience sweep: {restamps} restamps, {cold} cold items, {errors} date errors (details via /memory-checkup)")
'
else
  # Inline checks A, B, D from /memory-checkup Step 1 (same logic, safer extraction),
  # once per memory root (memory/ plus every areas/<name>/memory/ with a MEMORY.md).
  ROOTS="memory"
  for d in areas/*/memory; do [ -f "$d/MEMORY.md" ] && ROOTS="$ROOTS $d"; done
  for R in $ROOTS; do
    grep -nE '^- \[[^]]+\]\([^)]+\.md\)' "$R/MEMORY.md" | while IFS=: read -r ln rest; do
      tmp="${rest#*\(}"
      relpath="${tmp%%\)*}"
      [ -f "$R/$relpath" ] || echo "ORPHAN ROW ($R/MEMORY.md line $ln): $R/$relpath does not exist"
    done
    for f in "$R"/*.md; do
      base=$(basename "$f")
      case "$base" in MEMORY.md|REFERENCES.md|CLAUDE.md|INDEX.generated.md|*_template.md|*_example.md) continue ;; esac
      cat "$R/MEMORY.md" "$R/REFERENCES.md" 2>/dev/null | grep -q "($base)" \
        || echo "ORPHAN FILE: $f has no row in $R/MEMORY.md or $R/REFERENCES.md"
    done
    { find "$R" -maxdepth 1 -name 'project_*.md'; find "$R" -maxdepth 1 -name 'strategic_*.md'; } 2>/dev/null | while IFS= read -r f; do
      base=$(basename "$f")
      case "$base" in *_template.md|*_example.md) continue ;; esac
      fm=$(awk '/^---$/{if(x)exit;x=1;next} x && /^status:/{sub(/^status:[[:space:]]*/,""); print; exit}' "$f")
      row=$(grep -F "($base)" "$R/MEMORY.md" | head -1)
      if [ -n "$fm" ] && [ -n "$row" ]; then
        case "$row" in *"$fm"*) : ;; *) echo "EMOJI MISMATCH: $base frontmatter is $fm but its index row differs" ;; esac
      fi
    done
  done
  echo "(inline pass only; run /memory-checkup for the full sweep, including archive and wikilink checks)"
fi
```

`ADOPTED` detects `docs/ADVANCED.md` the same way the three advanced-layer
hooks in the other skills do: by whether any project or strategic file
actually carries a `salience` field, never by assuming. If it is `0`, or
`PY_OK` is `0`, or the script is missing, fall back to the inline pass:
checks A (orphan index rows), B (active files with no index row), and D
(frontmatter status vs. index emoji) from `/memory-checkup` Step 1, same
detection logic and output shape, with one deliberate difference: the field
extraction inside each loop uses a single `awk` call or plain parameter
expansion instead of a piped `awk | grep | sed` chain. That is a genuine
improvement on its own, fewer forked processes per iteration, independent of
any shell quirk.

If a command is reported as not found mid-run, rerun the block under bash
before treating it as a finding (see `reference/incidents.md`, row
`zsh-loop-lookup`). This inline pass is a summary, not the full sweep: it
skips the archive-listing check (C) and the wikilink check (E); say so and
point at `/memory-checkup` for those. The `"$R"/*.md` glob is safe
unguarded: every root in `ROOTS` holds a `MEMORY.md` by construction, so it
never has zero matches.

---

## Step 6: Git layer (governance pack, degrades gracefully)

Two halves: a local one that needs no tool, and a GitHub one gated on `gh`.

The local half is the coherence check of `docs/GOVERNANCE.md` step 3. It is inert
while `.github/sensitive-paths.txt` has no active pattern, and otherwise reports an
active list with no `sensitive_owner`, an owner without a `github` value, a clone
whose `core.hooksPath` is not `githooks`, a missing tripwire workflow, and drift
between the pattern list and CODEOWNERS in both directions:

```bash
cd "$(git rev-parse --show-toplevel)"
if [ -f scripts/governance-check.sh ]; then
  bash scripts/governance-check.sh
else
  echo "skipped: governance check (scripts/governance-check.sh absent)"
fi
```

Each `FINDING:` line is one finding for Step 7, with the fix it names. The `inactive`
line is not a finding: a team that has not adopted step 3 is in a normal state.

The GitHub half has no local artifact to check for "is `docs/GOVERNANCE.md` step 1
adopted": branch protection is a GitHub-side setting with nothing written into the
repo itself. So adoption is detected by the same call that reports on it, gated first
on whether that call can even be made:

```bash
cd "$(git rev-parse --show-toplevel)"
if [ "$GH_OK" != 1 ]; then
  echo "skipped: gh not authenticated"
elif [ "$REMOTE_OK" != 1 ]; then
  echo "skipped: no origin remote configured"
else
  gh api "repos/{owner}/{repo}/branches/main/protection" \
    --jq '{enforce_admins: .enforce_admins.enabled, linear: .required_linear_history.enabled, force_push: .allow_force_pushes.enabled, deletions: .allow_deletions.enabled}' 2>/dev/null \
    || echo "skipped: governance step 1 not adopted (no branch protection configured)"
  if [ -f .github/CODEOWNERS ]; then
    gh api "repos/{owner}/{repo}/codeowners/errors" --jq '.errors | length'
  else
    echo "skipped: governance step 3 not adopted (.github/CODEOWNERS not present)"
  fi
  # pull requests nobody has reviewed, opened before today: an ISO date compares as a string
  gh pr list --state open --json number,title,createdAt,reviewDecision \
    --jq '.[] | select(.reviewDecision == "" and (.createdAt[0:10]) < "'"$TODAY"'") | "UNREVIEWED PR #\(.number) (\(.title)) opened \(.createdAt[0:10])"' 2>/dev/null \
    || echo "skipped: could not list pull requests"
fi
```

Expected values when `docs/GOVERNANCE.md` step 1 is active: `enforce_admins:
true`, `linear: true`, `force_push: false`, `deletions: false`; CODEOWNERS
errors `0`. Any drift from those values is a finding, propose the exact `gh
api` fix already written in `docs/GOVERNANCE.md` step 1, never apply it
unasked, branch protection is repo-admin territory. An UNREVIEWED PR line is a
finding: propose `/pr-review <n>`.

---

## Step 7: Present findings

Present findings in this order: security, structure, registry, memory,
skills, git layer. Go through them **one at a time**: state the issue, give
enough context to judge it, propose a specific action, wait for the answer
before moving to the next one. Obvious quick fixes (several missing
`Context.md` stubs, several skills missing the footer) can be batched into a
single "these are quick fixes, all of them?" question, never applied
silently.

Close every run with the explicit list of what was skipped and why, pulled
from Step 0's probe and Step 6's own skip messages, even on a clean run.
"Skipped" is always reported, it is never silent, and it is not the same
thing as "clean": say plainly which is which.

Apply only what the operator approves. A `CLAUDE.md` edit proposed in Step 3
always needs its own explicit approval, separate from the rest of the batch,
per the root `CLAUDE.md` rule.

---

## Rules

- **Nothing without approval.** Every change needs explicit sign-off from
  the operator.
- **One item at a time.** State it, discuss it, act on it, move on.
- **Be honest.** If the system is clean, say so. Do not invent findings to
  justify the run.
- **Skipped is always reported, never silent.** A missing tool narrows the
  checkup; it does not let it fail quietly or pretend the check ran.
- **Quick fixes can be batched.** Ask once for the whole obvious set, never
  apply any of them without asking.
- **`CLAUDE.md` changes always need their own approval**, separate from
  everything else in the batch.
- **Convert relative dates to absolute** in anything written to a file.

## Self-improvement

At the end of the run, check it against these friction triggers: **avoidable
round-trip · improvisation · breakage · token waste · operator correction**
(full definitions in `skills/_improvements/capture.md`). If at least one fired,
ask the operator "there was friction on X, should I log it?"; on their ok,
append an entry to `skills/_improvements/friction-log.md` in the format
`capture.md` defines. Clean run: say nothing. Never self-edit this skill;
improvements go through `/skill-improve`.
