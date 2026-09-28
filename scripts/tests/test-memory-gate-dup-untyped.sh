#!/usr/bin/env bash
set -eu
ROOT="$(git rev-parse --show-toplevel)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash "$ROOT/scripts/tests/fixtures/make_memory_fixture.sh" "$T" >/dev/null

# 1. DUP-STEM: archiving by copy is a blocking finding, not an execution error
cp "$T/memory/project_alpha.md" "$T/memory/archive/project_alpha.md"
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only DUP-STEM > "$T/o.json" \
  || { echo "FAIL: gate died on a duplicate stem"; exit 1; }
python3 -c '
import json
d = json.load(open("'"$T"'/o.json"))
f = [x for x in d["findings"] if x["check"] == "DUP-STEM"]
assert len(f) == 1 and f[0]["target"] == "project_alpha.md", f
assert f[0]["severity"] == "error" and f[0]["blocking"] is True, f
print("OK: dup-stem finding")
'
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only ORPHAN > "$T/o2.json" \
  || { echo "FAIL: gate died on a duplicate stem with ORPHAN"; exit 1; }
python3 -c '
import json
d = json.load(open("'"$T"'/o2.json"))
assert d["graph"]["nucleus_size"] == 3, d["graph"]   # the active file wins, the graph is intact
print("OK: dup-stem graph intact")
'
rm "$T/memory/archive/project_alpha.md"

# 2. UNTYPED: a nested legacy schema is a warning, the file does not vanish silently
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only UNTYPED | python3 -c '
import json, sys
d = json.load(sys.stdin)
t = {f["target"] for f in d["findings"] if f["check"] == "UNTYPED"}
assert t == {"project_nested.md"}, t
f = d["findings"][0]
assert f["severity"] == "warning" and f["blocking"] is False, f
print("OK: untyped finding")
'
