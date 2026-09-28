#!/usr/bin/env bash
# Federated roots in the gate, and the opt-in property: with no area root the
# gate reports exactly what it reported before federation existed.
set -eu
ROOT="$(git rev-parse --show-toplevel)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash "$ROOT/scripts/tests/fixtures/make_memory_fixture.sh" "$T" >/dev/null

# 0. Opt-in off: a full run with no area root, then again with an areas/ tree that holds
#    no MEMORY.md. Same finding ids, one index in index_bytes, nothing about roots.
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 > "$T/plain.json" || true
mkdir -p "$T/areas/clients/memory" "$T/areas/content"
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 > "$T/plain2.json" || true
python3 - "$T" <<'EOF'
import json, sys
a = json.load(open(sys.argv[1] + "/plain.json")); b = json.load(open(sys.argv[1] + "/plain2.json"))
assert {f["id"] for f in a["findings"]} == {f["id"] for f in b["findings"]}, (a["findings"], b["findings"])
assert b["index_bytes"] == {"MEMORY.md": b["memory_md_bytes"]}, b["index_bytes"]
assert not any("areas/" in f["id"] or f["check"] == "DUP-ROOT" for f in b["findings"]), b["findings"]
print("OK: roots off = pre-federation findings")
EOF

bash "$ROOT/scripts/tests/fixtures/add_area_fixture.sh" "$T" >/dev/null

# 1. Corpus = union of the roots: a cross-root link resolves, DUP-ROOT on the duplicate,
#    INDEX-ROW per root
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 \
  --only BROKEN,DUP-ROOT,DUP-STEM,INDEX-ROW | python3 -c '
import json, sys
d = json.load(sys.stdin)
ids = {f["id"] for f in d["findings"]}
assert not any(i.startswith("BROKEN:project_ops_one.md") for i in ids), ids   # [[project_beta]] resolves from the primary
assert "DUP-ROOT:project_alpha.md" in ids, ids
dr = [f for f in d["findings"] if f["check"] == "DUP-ROOT"][0]
assert dr["blocking"] is True and "memory/project_alpha.md" in dr["detail"] \
    and "areas/operations/memory/project_alpha.md" in dr["detail"], dr
assert "DUP-STEM:project_alpha.md" not in ids, ids
assert "INDEX-ROW:areas/operations/memory/project_ops_unlisted.md" in ids, ids   # active, no row in the AREA index
assert "INDEX-ROW:project_unlisted.md" in ids, ids       # the primary check still runs
assert "INDEX-ROW:archive/project_ops_closed.md" not in ids, ids   # listed in the area archive index
print("OK: roots corpus")
'

# 2. BUDGET per index: the area index has its own cap and its own target
MEMORY_GATE_AREA_LIMIT_BYTES=10 python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only BUDGET | python3 -c '
import json, sys
d = json.load(sys.stdin)
ids = {f["id"] for f in d["findings"]}
assert "BUDGET:areas/operations/memory/MEMORY.md" in ids, ids
assert "BUDGET:MEMORY.md" not in ids, ids
assert d["memory_md_bytes"] == d["index_bytes"]["MEMORY.md"] and "areas/operations/memory/MEMORY.md" in d["index_bytes"], d
print("OK: roots budget")
'

# 3. ROW-BUDGET per index
MEMORY_GATE_ROW_LIMIT_BYTES=10 python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only ROW-BUDGET | python3 -c '
import json, sys
d = json.load(sys.stdin)
t = {f["target"] for f in d["findings"]}
assert t == {"MEMORY.md", "areas/operations/memory/MEMORY.md"}, t
print("OK: roots row-budget")
'

# 4. STALE-INDEX per root
python3 "$ROOT/scripts/build_index.py" --repo "$T" --write >/dev/null
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only STALE-INDEX \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["green"], d; print("OK: roots stale fresh")'
printf '\n## Next action\nChanged again.\n' >> "$T/areas/operations/memory/project_ops_one.md"
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only STALE-INDEX | python3 -c '
import json, sys
d = json.load(sys.stdin)
ids = {f["id"] for f in d["findings"]}
assert ids == {"STALE-INDEX:areas/operations/memory/INDEX.generated.md"}, ids
print("OK: roots stale per root")
'

# 5. ## Areas pointers: a root without a pointer row, and a pointer row without a root
python3 - "$T" <<'EOF'
import sys
p = sys.argv[1] + "/memory/MEMORY.md"
t = open(p, encoding="utf-8").read().replace(
    "- [Operations](../areas/operations/memory/MEMORY.md)",
    "- [Ghost](../areas/ghost/memory/MEMORY.md)")
open(p, "w", encoding="utf-8").write(t)
EOF
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only INDEX-ROW | python3 -c '
import json, sys
d = json.load(sys.stdin)
ids = {f["id"] for f in d["findings"]}
assert "INDEX-ROW:areas/operations/memory/MEMORY.md" in ids, ids
assert "INDEX-ROW:areas/ghost/memory/MEMORY.md" in ids, ids
print("OK: roots area pointers")
'
echo "OK: memory-gate roots"
