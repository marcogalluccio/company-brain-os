#!/usr/bin/env bash
set -eu
ROOT="$(git rev-parse --show-toplevel)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash "$ROOT/scripts/tests/fixtures/make_memory_fixture.sh" "$T" >/dev/null

# 1. INDEX-ROW: ghost row, unlisted file, emoji mismatch; nothing on a coherent file
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only INDEX-ROW | python3 -c '
import json, sys
d = json.load(sys.stdin)
ids = {f["id"] for f in d["findings"]}
assert "INDEX-ROW:project_ghost.md" in ids, ids
assert "INDEX-ROW:project_unlisted.md" in ids, ids
assert "INDEX-ROW:project_alpha.md" in ids, ids
assert not any("beta" in i for i in ids), ids
print("OK: index-row")
'

# 2. BUDGET: green by default, warning between 90% and 100%, blocking error above
SIZE=$(python3 -c "import os; print(os.path.getsize('$T/memory/MEMORY.md'))")
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only BUDGET \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["green"], d; print("OK: budget green")'
MEMORY_GATE_LIMIT_BYTES=$((SIZE * 105 / 100)) python3 "$ROOT/scripts/memory_gate.py" \
  --repo "$T" --as-of 2026-07-05 --only BUDGET | python3 -c '
import json, sys
d = json.load(sys.stdin)
f = d["findings"][0]
assert f["check"] == "BUDGET" and f["severity"] == "warning" and f["blocking"] is False, f
print("OK: budget warning 90%")
'
set +e
MEMORY_GATE_LIMIT_BYTES=100 python3 "$ROOT/scripts/memory_gate.py" \
  --repo "$T" --as-of 2026-07-05 --only BUDGET --strict > "$T/out.json"; rc=$?
set -e
[ "$rc" = 1 ] || { echo "FAIL: --strict with BUDGET over the limit should exit 1 (rc=$rc)"; exit 1; }
python3 -c '
import json
d = json.load(open("'"$T"'/out.json"))
f = d["findings"][0]
assert f["severity"] == "error" and f["blocking"] is True, f
assert d["memory_md_bytes"] > 100
print("OK: budget error + strict")
'

# 3. ROW-BUDGET: green with a high fixed cap; one aggregated warning with a low one;
#    with no override the cap is derived from the file and only the heavy rows exceed it
MEMORY_GATE_ROW_LIMIT_BYTES=9999 python3 "$ROOT/scripts/memory_gate.py" \
  --repo "$T" --as-of 2026-07-05 --only ROW-BUDGET | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["green"] and not d["findings"], d
print("OK: row-budget green")
'
MEMORY_GATE_ROW_LIMIT_BYTES=10 python3 "$ROOT/scripts/memory_gate.py" \
  --repo "$T" --as-of 2026-07-05 --only ROW-BUDGET | python3 -c '
import json, sys
d = json.load(sys.stdin)
fs = d["findings"]
assert len(fs) == 1, "one aggregated finding, not one per row: %d" % len(fs)
f = fs[0]
assert f["check"] == "ROW-BUDGET" and f["target"] == "MEMORY.md", f
assert f["severity"] == "warning" and f["blocking"] is False, f
assert "Heaviest:" in f["detail"] and "excess" in f["detail"], f
print("OK: row-budget aggregated warning")
'
# Derived cap: choose a file cap that leaves ~40 B per row after the fixed prose.
LIMIT=$(python3 - "$T" <<'EOF'
import os, re, sys
p = sys.argv[1] + "/memory/MEMORY.md"
rows = [len(l.rstrip("\n").encode()) for l in open(p, encoding="utf-8")
        if re.match(r"^- \[[^\]]+\]\([A-Za-z0-9_\-/]+\.md\)", l.strip())]
prose = os.path.getsize(p) - sum(rows)
print(prose + int(len(rows) * 1.25 * 40))
EOF
)
MEMORY_GATE_LIMIT_BYTES=$LIMIT python3 "$ROOT/scripts/memory_gate.py" \
  --repo "$T" --as-of 2026-07-05 --only ROW-BUDGET | python3 -c '
import json, sys
d = json.load(sys.stdin)
f = d["findings"][0]
assert "project_alpha.md" in f["detail"], f          # the longest row, with the folder pointer
assert "feedback_note.md" not in f["detail"], f      # a short row stays under the derived cap
print("OK: row-budget derived cap")
'
