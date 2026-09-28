#!/usr/bin/env bash
# The deterministic checks of /memory-checkup are shell snippets inside SKILL.md.
# This extracts the Step 1 block and runs it against two fixtures: the split
# layout (index rows spread across MEMORY.md/REFERENCES.md/archive/INDEX.md)
# and the inline layout (everything inside MEMORY.md). A skill edit that
# breaks either one fails here instead of at the next live checkup. Each case
# below is chosen so it can only pass if the block resolves the right path
# against the right file: a wrong prefix (e.g. resolving an archive row against
# the repo root instead of memory/archive/) makes the specific assertion fail,
# not just "some line was printed".
set -eu
ROOT="$(git rev-parse --show-toplevel)"
T=$(mktemp -d)
T2=$(mktemp -d)
trap 'rm -rf "$T" "$T2"' EXIT
bash "$ROOT/scripts/tests/fixtures/make_memory_fixture.sh" "$T" >/dev/null
awk '/^## Step 1: Deterministic checks/{s=1} s && /^```bash$/{b=1; next} b && /^```$/{exit} b' \
  "$ROOT/skills/memory-checkup/SKILL.md" > "$T/step1.sh"
[ -s "$T/step1.sh" ] || { echo "FAIL: Step 1 block not found"; exit 1; }
if grep -qE '\$[0-9]' "$T/step1.sh"; then echo "FAIL: positional parameter in a skill snippet"; exit 1; fi

# ---------------------------------------------------------------------------
# SECTION 1: split layout, as the template ships it. This owns $T.
# ---------------------------------------------------------------------------

python3 - "$T" <<'EOF'
import sys
p = sys.argv[1] + "/memory/MEMORY.md"
t = open(p, encoding="utf-8").read()
t = t.replace("- [Standalone](reference_standalone.md) - pointer\n", "Pointers in [REFERENCES.md](REFERENCES.md).\n")
t = t.replace("- [Closed](archive/project_closed.md) - ❌ closed 2026-06-01\n", "Closed items in [archive/INDEX.md](archive/INDEX.md).\n")
open(p, "w", encoding="utf-8").write(t)
# A ghost row in REFERENCES.md: check A's REFERENCES.md arm must resolve it as
# memory/reference_ghost.md (the same "memory/$relpath" rule as MEMORY.md rows),
# not silently pass because that arm never runs.
open(sys.argv[1] + "/memory/REFERENCES.md", "w", encoding="utf-8").write(
    "# References\n\n"
    "- [Standalone](reference_standalone.md) - pointer\n"
    "- [Ghost Ref](reference_ghost.md) - pointer\n"
)
# A ghost row in archive/INDEX.md: rows there are relative to memory/archive/,
# not memory/ or the repo root, so this only passes if that prefix is right.
open(sys.argv[1] + "/memory/archive/INDEX.md", "w", encoding="utf-8").write(
    "# Archive\n\n"
    "- [Closed](project_closed.md) - ❌ closed 2026-06-01\n"
    "- [Vanished](project_vanished.md) - ❌ closed 2026-01-01\n"
)
EOF
cat > "$T/memory/archive/project_forgotten.md" <<'EOF'
---
name: project_forgotten
type: project
status: ❌
owner: operator-one
---
## Status
❌ Closed, never listed.
EOF
git -C "$T" init -q
( cd "$T" && bash "$T/step1.sh" ) > "$T/out.txt" 2>&1 || true

grep -q "ORPHAN ROW (memory/MEMORY.md line" "$T/out.txt" || { echo "FAIL: ghost row not reported"; cat "$T/out.txt"; exit 1; }
grep -q "ORPHAN FILE: memory/project_unlisted.md" "$T/out.txt" || { echo "FAIL: unlisted file not reported"; cat "$T/out.txt"; exit 1; }
grep -q "UNLISTED ARCHIVE: memory/archive/project_forgotten.md" "$T/out.txt" || { echo "FAIL: unlisted archive not reported"; cat "$T/out.txt"; exit 1; }
grep -q "EMOJI MISMATCH: project_alpha.md" "$T/out.txt" || { echo "FAIL: emoji mismatch not reported"; cat "$T/out.txt"; exit 1; }
grep -q "BROKEN LINK: \[\[ghost_target\]\]" "$T/out.txt" || { echo "FAIL: broken link not reported"; cat "$T/out.txt"; exit 1; }
grep -qE "ORPHAN ROW \(memory/REFERENCES\.md line [0-9]+\): memory/reference_ghost\.md does not exist" "$T/out.txt" \
  || { echo "FAIL: ghost row in REFERENCES.md not reported with the right path"; cat "$T/out.txt"; exit 1; }
grep -qE "ORPHAN ROW \(memory/archive/INDEX\.md line [0-9]+\): memory/archive/project_vanished\.md does not exist" "$T/out.txt" \
  || { echo "FAIL: ghost row in archive/INDEX.md not reported with the right path"; cat "$T/out.txt"; exit 1; }
if grep -q "reference_standalone" "$T/out.txt"; then echo "FAIL: reference row in REFERENCES.md reported as orphan"; cat "$T/out.txt"; exit 1; fi
if grep -q "project_closed" "$T/out.txt"; then echo "FAIL: archived file listed in archive/INDEX.md reported"; cat "$T/out.txt"; exit 1; fi
if grep -E "(ORPHAN FILE|BROKEN LINK|EMOJI MISMATCH).*INDEX\.md" "$T/out.txt"; then echo "FAIL: an index file was treated as a memory file"; cat "$T/out.txt"; exit 1; fi
echo "OK: memory-checkup step 1 block (split layout)"

# ---------------------------------------------------------------------------
# SECTION 2: inline layout, everything lives inside MEMORY.md and there
# is no REFERENCES.md or archive/INDEX.md. This must keep working identically.
# This owns $T2.
# ---------------------------------------------------------------------------

bash "$ROOT/scripts/tests/fixtures/make_memory_fixture.sh" "$T2" >/dev/null
cp "$T/step1.sh" "$T2/step1.sh"
# The fixture's own inline "## References" and "## Archive" sections already
# exercise the happy path (a real reference row, a real archived row). Add one
# ghost row under each so the inline arm can fail too, the same way section 1
# does for the split files.
python3 - "$T2" <<'EOF'
import sys
p = sys.argv[1] + "/memory/MEMORY.md"
t = open(p, encoding="utf-8").read()
t = t.replace(
    "- [Standalone](reference_standalone.md) - pointer\n",
    "- [Standalone](reference_standalone.md) - pointer\n- [Ghost Ref](reference_ghost_inline.md) - pointer\n",
)
open(p, "w", encoding="utf-8").write(t)
EOF
cat > "$T2/memory/archive/project_forgotten_inline.md" <<'EOF'
---
name: project_forgotten_inline
type: project
status: ❌
owner: operator-one
---
## Status
❌ Closed, never listed.
EOF
git -C "$T2" init -q
( cd "$T2" && bash "$T2/step1.sh" ) > "$T2/out.txt" 2>&1 || true

grep -qE "ORPHAN ROW \(memory/MEMORY\.md line [0-9]+\): memory/reference_ghost_inline\.md does not exist" "$T2/out.txt" \
  || { echo "FAIL: inline layout: ghost reference row not reported"; cat "$T2/out.txt"; exit 1; }
grep -q "UNLISTED ARCHIVE: memory/archive/project_forgotten_inline.md" "$T2/out.txt" \
  || { echo "FAIL: inline layout: unlisted archived file not reported"; cat "$T2/out.txt"; exit 1; }
if grep -q "reference_standalone" "$T2/out.txt"; then echo "FAIL: inline layout: listed reference row reported as orphan"; cat "$T2/out.txt"; exit 1; fi
if grep -q "project_closed" "$T2/out.txt"; then echo "FAIL: inline layout: archived file listed under ## Archive reported"; cat "$T2/out.txt"; exit 1; fi
echo "OK: memory-checkup step 1 block (inline layout)"

# Area root: the same block must check areas/<name>/memory/ and resolve links across roots
bash "$ROOT/scripts/tests/fixtures/add_area_fixture.sh" "$T" >/dev/null
( cd "$T" && bash "$T/step1.sh" ) > "$T/out2.txt" 2>&1 || true
grep -q "ORPHAN FILE: areas/operations/memory/project_ops_unlisted.md" "$T/out2.txt" || { echo "FAIL: unlisted area file not reported"; cat "$T/out2.txt"; exit 1; }
if grep -q "BROKEN LINK: \[\[project_beta\]\]" "$T/out2.txt"; then echo "FAIL: cross-root link reported as broken"; cat "$T/out2.txt"; exit 1; fi
if grep "ORPHAN ROW (memory/MEMORY.md" "$T/out2.txt" | grep -q "operations"; then echo "FAIL: the ## Areas pointer row reported as orphan"; cat "$T/out2.txt"; exit 1; fi
if grep -q "project_ops_closed" "$T/out2.txt"; then echo "FAIL: archived area file listed in its archive/INDEX.md reported"; cat "$T/out2.txt"; exit 1; fi
echo "OK: memory-checkup step 1 block with an area root"
