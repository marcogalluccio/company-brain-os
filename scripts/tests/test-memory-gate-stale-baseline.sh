#!/usr/bin/env bash
set -eu
ROOT="$(git rev-parse --show-toplevel)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash "$ROOT/scripts/tests/fixtures/make_memory_fixture.sh" "$T" >/dev/null

# 1. Missing generated index is informational, not stale
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only STALE-INDEX | python3 -c '
import json, sys
d = json.load(sys.stdin)
f = d["findings"][0]
assert f["check"] == "STALE-INDEX" and f["severity"] == "info", f
print("OK: stale-index missing=info")
'

# 2. Fresh is green; touching a source turns it into a warning
python3 "$ROOT/scripts/build_index.py" --repo "$T" --write >/dev/null
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only STALE-INDEX \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["green"], d; print("OK: stale-index fresh")'
printf '\n## Next action\nChanged now.\n' >> "$T/memory/project_beta.md"
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only STALE-INDEX | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["findings"][0]["severity"] == "warning", d
print("OK: stale-index warning")
'

# 3. Baseline: save a full run; fix an orphan and break a link; the delta reflects both
python3 "$ROOT/scripts/build_index.py" --repo "$T" --write >/dev/null
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 > "$T/base.json" || true
printf '\nSee also [[project_orphan]].\n' >> "$T/memory/project_alpha.md"
printf '\nAnd [[new_broken_link]].\n' >> "$T/memory/project_beta.md"
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --baseline "$T/base.json" > "$T/run2.json" || true
python3 -c '
import json
d = json.load(open("'"$T"'/run2.json"))
delta = d["delta"]
assert "BROKEN:project_beta.md:new_broken_link" in delta["new"], delta
assert "ORPHAN:project_orphan.md" in delta["resolved"], delta
assert delta["baseline_id"] and delta["baseline_tree_hash"] != d["tree_hash"], delta
print("OK: baseline delta")
'
