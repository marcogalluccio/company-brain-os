#!/usr/bin/env bash
# Invariant: across one gate run, finding ids are unique. Two different
# findings sharing an id are indistinguishable to an allowlist entry, to
# compute_delta's new/resolved diff, and to a human reading either one's
# target: one silences both, and a fix to one goes unreported.
#
# Fixture: an item's file is moved into an area root but its index row is
# left behind in the primary, and the area gains no row of its own: the
# half-finished state of moving an item into an area (file moved, row not).
# No DUP-STEM/DUP-ROOT fires: the stem exists on disk in exactly one root.
set -eu
ROOT="$(git rev-parse --show-toplevel)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash "$ROOT/scripts/tests/fixtures/make_memory_fixture.sh" "$T" >/dev/null
bash "$ROOT/scripts/tests/fixtures/add_area_fixture.sh" "$T" >/dev/null

# The file lives in the area only now; the primary's row for it is stale, and
# the area never got a row of its own (dropped here, standing in for a row
# that was simply never added).
rm "$T/memory/project_alpha.md"
python3 - "$T" <<'EOF'
import sys
p = sys.argv[1] + "/areas/operations/memory/MEMORY.md"
t = open(p, encoding="utf-8").read()
kept = [l for l in t.splitlines(keepends=True) if "project_alpha.md" not in l]
open(p, "w", encoding="utf-8").write("".join(kept))
EOF

python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 \
  --only INDEX-ROW,DUP-STEM,DUP-ROOT | python3 -c '
import json, sys
d = json.load(sys.stdin)
findings = d["findings"]
assert not any(f["check"] in ("DUP-STEM", "DUP-ROOT") for f in findings), findings
ids = [f["id"] for f in findings]
assert len(ids) == len(set(ids)), ("duplicate finding ids", ids)
targets = {f["target"] for f in findings if f["check"] == "INDEX-ROW"}
assert "project_alpha.md" in targets, targets                              # primary: stale row
assert "areas/operations/memory/project_alpha.md" in targets, targets      # area: unlisted file
print("OK: finding ids unique across roots")
'
echo "OK: memory-gate finding ids"
