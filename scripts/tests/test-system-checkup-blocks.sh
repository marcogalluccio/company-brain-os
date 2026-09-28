#!/usr/bin/env bash
# /system-checkup Step 5 carries its own inline reimplementation of checks
# A, B, D from /memory-checkup Step 1 (for when the advanced layer is not
# adopted, or scripts/memory_gate.py is unavailable) with deliberately
# different shell: parameter expansion instead of a sed capture, one fused
# awk instead of a piped chain. That divergence is exactly the kind of thing
# that silently drifts, so this extracts the fenced block and drives it the
# same way test-memory-checkup-blocks.sh drives Step 1: against a fixture
# built for the purpose, once with no area root and once with one.
set -eu
ROOT="$(git rev-parse --show-toplevel)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash "$ROOT/scripts/tests/fixtures/make_memory_fixture.sh" "$T" >/dev/null

awk '/^## Step 5: Memory summary/{s=1} s && /^```bash$/{b=1; next} b && /^```$/{exit} b' \
  "$ROOT/skills/system-checkup/SKILL.md" > "$T/step5.sh"
[ -s "$T/step5.sh" ] || { echo "FAIL: Step 5 block not found"; exit 1; }
if grep -qE '\$[0-9]' "$T/step5.sh"; then echo "FAIL: positional parameter in a skill snippet"; exit 1; fi

# No scripts/memory_gate.py in the fixture, so the block's own guard takes the
# inline branch regardless of PY_OK; set it explicitly anyway so the fixture
# does not depend on the guard's exact shape.
git -C "$T" init -q
( cd "$T" && PY_OK=0 bash "$T/step5.sh" ) > "$T/out.txt" 2>&1 || true

# --- no area root ---
grep -q "ORPHAN ROW (memory/MEMORY.md line" "$T/out.txt" || { echo "FAIL: ghost row not reported"; cat "$T/out.txt"; exit 1; }
grep -q "ORPHAN FILE: memory/project_unlisted.md" "$T/out.txt" || { echo "FAIL: unlisted file not reported"; cat "$T/out.txt"; exit 1; }
grep -q "EMOJI MISMATCH: project_alpha.md" "$T/out.txt" || { echo "FAIL: emoji mismatch not reported"; cat "$T/out.txt"; exit 1; }
if grep -q "reference_standalone" "$T/out.txt"; then echo "FAIL: reference row reported as orphan"; cat "$T/out.txt"; exit 1; fi
if grep -q "project_closed" "$T/out.txt"; then echo "FAIL: archived file reported (Step 5 skips the archive check on purpose)"; cat "$T/out.txt"; exit 1; fi
if grep -q "BROKEN LINK" "$T/out.txt"; then echo "FAIL: Step 5 does not implement the wikilink check, but reported one"; cat "$T/out.txt"; exit 1; fi
if grep -E "(ORPHAN FILE|EMOJI MISMATCH).*INDEX\.md" "$T/out.txt"; then echo "FAIL: an index file was treated as a memory file"; cat "$T/out.txt"; exit 1; fi
grep -q "inline pass only" "$T/out.txt" || { echo "FAIL: missing the inline-pass disclosure line"; cat "$T/out.txt"; exit 1; }
echo "OK: system-checkup step 5 block (no area root)"

# --- area root ---
bash "$ROOT/scripts/tests/fixtures/add_area_fixture.sh" "$T" >/dev/null
( cd "$T" && PY_OK=0 bash "$T/step5.sh" ) > "$T/out2.txt" 2>&1 || true
grep -q "ORPHAN FILE: areas/operations/memory/project_ops_unlisted.md" "$T/out2.txt" || { echo "FAIL: unlisted area file not reported"; cat "$T/out2.txt"; exit 1; }
if grep "ORPHAN ROW (memory/MEMORY.md" "$T/out2.txt" | grep -q "operations"; then echo "FAIL: the ## Areas pointer row reported as orphan"; cat "$T/out2.txt"; exit 1; fi
if grep -q "project_ops_closed" "$T/out2.txt"; then echo "FAIL: archived area file reported"; cat "$T/out2.txt"; exit 1; fi
if grep -q "ORPHAN FILE: areas/operations/memory/project_ops_one.md" "$T/out2.txt"; then echo "FAIL: area file with a row reported as orphan"; cat "$T/out2.txt"; exit 1; fi
if grep -q "ORPHAN FILE: areas/operations/memory/project_alpha.md" "$T/out2.txt"; then echo "FAIL: area file with a row reported as orphan"; cat "$T/out2.txt"; exit 1; fi
echo "OK: system-checkup step 5 block with an area root"
