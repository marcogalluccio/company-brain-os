---
name: memory-checkup
description: |
  Memory hygiene pass: finds drift between memory/MEMORY.md and the files on
  disk, and proposes fixes one at a time. Deterministic checks first, judgment
  checks second, nothing written without approval.
  Use when the operator says: memory checkup, /memory-checkup, check the
  memory, memory review.
---

# Memory Checkup

The memory layer drifts in small, mechanical ways: an index row survives a
file that got renamed, a new project file never gets a row, a file moves to
`memory/archive/` but its row never follows into `memory/archive/INDEX.md`,
a status changes in the frontmatter but not in the index line next to it, a
wikilink points at a file that no longer exists. None of these need
judgment to find, only judgment to fix, so this skill runs the deterministic
sweep first and only reasons about the rest once that sweep is clean.

Run the steps in order.

---

## Step 1: Deterministic checks

Run these blocks verbatim from the repo root. Each one prints findings on
stdout; empty output means that check is clean. Every check skips
`MEMORY.md`, `REFERENCES.md`, `CLAUDE.md`, `INDEX.generated.md`,
`archive/INDEX.md`, `*_template.md`, and `*_example` stems, everywhere those
apply, per the shipped memory conventions.

```bash
cd "$(git rev-parse --show-toplevel)"
# Memory roots: memory/ plus every areas/<name>/memory/ that holds a MEMORY.md
# (area names are slugs, so the space-separated list is safe to word-split).
# With no area root this is just "memory" and every check below runs once.
ROOTS="memory"
for d in areas/*/memory; do [ -f "$d/MEMORY.md" ] && ROOTS="$ROOTS $d"; done
for R in $ROOTS; do
  # Index rows may live in MEMORY.md, REFERENCES.md (reference_* rows) and
  # archive/INDEX.md (closed items, links relative to archive/).
  # A. Index rows pointing at missing files
  for idx in "$R/MEMORY.md" "$R/REFERENCES.md"; do
    [ -f "$idx" ] || continue
    grep -nE '^- \[[^]]+\]\([^)]+\.md\)' "$idx" | while IFS=: read -r ln rest; do
      relpath=$(echo "$rest" | sed -E 's/^- \[[^]]+\]\(([^)]+)\).*/\1/')
      [ -f "$R/$relpath" ] || echo "ORPHAN ROW ($idx line $ln): $R/$relpath does not exist"
    done
  done
  if [ -f "$R/archive/INDEX.md" ]; then
    grep -nE '^- \[[^]]+\]\([^)]+\.md\)' "$R/archive/INDEX.md" | while IFS=: read -r ln rest; do
      relpath=$(echo "$rest" | sed -E 's/^- \[[^]]+\]\(([^)]+)\).*/\1/')
      [ -f "$R/archive/$relpath" ] || echo "ORPHAN ROW ($R/archive/INDEX.md line $ln): $R/archive/$relpath does not exist"
    done
  fi
  # B. Active files without an index row (in MEMORY.md or REFERENCES.md of their root)
  for f in "$R"/*.md; do
    base=$(basename "$f")
    case "$base" in MEMORY.md|REFERENCES.md|CLAUDE.md|INDEX.generated.md|*_template.md|*_example.md) continue ;; esac
    cat "$R/MEMORY.md" "$R/REFERENCES.md" 2>/dev/null | grep -q "($base)" \
      || echo "ORPHAN FILE: $f has no row in $R/MEMORY.md or $R/REFERENCES.md"
  done
  # C. Archived files not listed (in archive/INDEX.md, or under ## Archive in MEMORY.md for a repo that never split it)
  find "$R/archive" -maxdepth 1 -name '*.md' ! -name 'INDEX.md' 2>/dev/null | while IFS= read -r f; do
    base=$(basename "$f")
    { [ -f "$R/archive/INDEX.md" ] && grep -q "($base)" "$R/archive/INDEX.md"; } \
      || awk '/^## Archive/,0' "$R/MEMORY.md" | grep -q "(archive/$base)" \
      || echo "UNLISTED ARCHIVE: $f has no row in $R/archive/INDEX.md"
  done
  # D. Frontmatter status vs index-row emoji
  { find "$R" -maxdepth 1 -name 'project_*.md'; find "$R" -maxdepth 1 -name 'strategic_*.md'; } 2>/dev/null | while IFS= read -r f; do
    base=$(basename "$f")
    case "$base" in *_template.md|*_example.md) continue ;; esac
    fm=$(awk '/^---$/{if(x)exit;x=1;next} x' "$f" | grep '^status:' | sed 's/status:[[:space:]]*//')
    row=$(grep -F "($base)" "$R/MEMORY.md" | head -1)
    if [ -n "$fm" ] && [ -n "$row" ]; then
      case "$row" in *"$fm"*) : ;; *) echo "EMOJI MISMATCH: $base frontmatter is $fm but its index row differs" ;; esac
    fi
  done
  # E. Broken wikilinks: a link resolves in ANY root, active or archived
  find "$R" "$R/archive" -maxdepth 1 -name '*.md' 2>/dev/null | while IFS= read -r f; do
    base=$(basename "$f")
    case "$base" in MEMORY.md|REFERENCES.md|CLAUDE.md|INDEX.generated.md|INDEX.md|*_template.md|*_example.md) continue ;; esac
    grep -oE '\[\[[A-Za-z0-9_-]+\]\]' "$f" 2>/dev/null | tr -d '[]' | sort -u | while read -r t; do
      found=0
      for R2 in $ROOTS; do
        { [ -f "$R2/$t.md" ] || [ -f "$R2/archive/$t.md" ]; } && found=1
      done
      [ "$found" = 1 ] || echo "BROKEN LINK: [[$t]] in $f"
    done
  done
done
```

Run every block even after an early one finds something: they are
independent, and Step 3 needs the full list before it starts proposing
fixes, not a partial one.

If `memory/MEMORY.md` has a `## Areas` section, the team has adopted federated
memory roots (`docs/ADVANCED.md` section 8) and the block above already loops
over every `areas/<name>/memory/` that holds a `MEMORY.md`. Without one it runs
once, on `memory/`, exactly as before.

Check E has no fenced-code-block awareness: a project file that quotes
`[[...]]` as documentation (explaining the wikilink convention, not using
it) will false-positive. This is a known limitation, not a bug to patch with
a fence parser: if a finding traces back to a quoted example rather than a
real link, dismiss it in Step 3 triage, and keep real links out of code
fences to avoid tripping this yourself.

---

## Step 2: Judgment checks

Once Step 1 is clean (or its findings are queued for Step 3), read
`memory/MEMORY.md` and the linked project and strategic files for what no
grep can catch on its own:

- **Stale statuses.** A `deadline` in the past on a file whose `status` is
  not `❌`. A `## Next action` that a recent daily log shows as already
  done, but the file was never updated to reflect it.
- **Duplicate index rows.** Two rows in `MEMORY.md` pointing at the same
  file, under the same section or different ones.

**Advanced-layer hook.** If project or strategic files carry `salience` or
`last_touched` frontmatter fields, the team has adopted `docs/ADVANCED.md`:
run the weekly sweep and list every file whose written `salience` drifted
from the recomputed value, plus the items the sweep flags as cold:

```bash
cd "$(git rev-parse --show-toplevel)"
if command -v python3 >/dev/null 2>&1 && [ -f scripts/salience_sweep.py ]; then
  python3 scripts/salience_sweep.py | python3 -c '
import json, sys
d = json.load(sys.stdin)
for r in d["restamps"]:
    root, file, written, computed, days = r["root"], r["file"], r["written"], r["computed"], r["days_idle"]
    print(f"RESTAMP {root}/{file}: {written} -> {computed} ({days} days idle)")
for e in d["emoji_suggestions"]:
    root, file, hint = e["root"], e["file"], e["hint"]
    print(f"COLD {root}/{file}: {hint}")
for e in d["errors"]:
    root, file, err = e["root"], e["file"], e["error"]
    print(f"DATE ERROR {root}/{file}: {err}")
'
else
  echo "sweep script unavailable: recompute by hand with the formula in docs/ADVANCED.md"
fi
```

The script is read-only and deterministic: the same corpus gives the same
numbers whether it or a human runs the formula. Restamps go to Step 3 as
proposals; a `COLD` line is a question for the operator (stall it, wrap it
up, or archive it?), never an automatic status change. If those fields are
not present on any file, the layer has not been adopted: skip this silently,
with no mention of it in the output.

---

## Step 3: Present and fix

Go through findings one at a time: state what was found, give enough
context to judge it (the file, the line, what's inconsistent), propose the
fix, and wait for the operator's answer before touching anything. The only
exception is a batch of obviously mechanical quick fixes (e.g. several
salience restamps from the advanced-layer hook, or several emoji
corrections that all just copy the frontmatter value into the index row):
those can be grouped into a single "apply all N?" question, but never
silently applied.

Apply approved fixes with Read-then-Edit, never a blind overwrite. An
archive move follows `memory/CLAUDE.md`: set `status: ❌` in both the
frontmatter and the body, `git mv` the file into `memory/archive/`, and move
its index line out of `MEMORY.md` into `memory/archive/INDEX.md` (link
relative to the archive folder, no `archive/` prefix). Never delete a memory
file; archive is the only close.

If Step 1 and Step 2 both come back clean, say so plainly and stop: "memory
is coherent, nothing to fix." Do not manufacture a finding to justify the
run.

---

## Rules

- **Deterministic checks first, judgment checks second.** Step 1 is grep and
  awk, not opinion; run it in full before reasoning about anything Step 2
  might add.
- **Propose, then write.** Every fix is stated, then approved, then applied.
  Nothing in this skill writes to memory unmoderated.
- **Archive, never delete.** Closing a file is a move plus a frontmatter and
  index change, never an `rm`.
- **The layer's standard is `memory/CLAUDE.md`.** Index-row format, the
  status/emoji scale, wikilink resolution, and the archive convention are
  defined there; if this skill's summary of a rule and that file ever seem
  to disagree, `memory/CLAUDE.md` wins.

## Self-improvement

At the end of the run, check it against these friction triggers: **avoidable
round-trip · improvisation · breakage · token waste · operator correction**
(full definitions in `skills/_improvements/capture.md`). If at least one fired,
ask the operator "there was friction on X, should I log it?"; on their ok,
append an entry to `skills/_improvements/friction-log.md` in the format
`capture.md` defines. Clean run: say nothing. Never self-edit this skill;
improvements go through `/skill-improve`.
