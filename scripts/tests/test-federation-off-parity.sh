#!/usr/bin/env bash
# Pins the opt-in property: with no areas/*/memory/MEMORY.md, the primary is
# THE only root, never one root among several. is_primary() is the single
# switch every script consults to draw that line; a regression that breaks
# it (say, a refactor that starts comparing against the first entry of
# memory_roots() instead of against the primary path by name) would not
# change memory_roots() itself, so test-memory-roots.sh's roots() == "memory"
# assertion stays green while every label downstream quietly flips to the
# root-qualified area form. This test exercises the three CLI entry points
# directly and pins the primary-only labels they emit, so that exact
# regression fails here instead of shipping silently.
set -eu
ROOT="$(git rev-parse --show-toplevel)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash "$ROOT/scripts/tests/fixtures/make_memory_fixture.sh" "$T" >/dev/null
# No area root is added on purpose: this fixture is federation-off.

# 1. Before any index file exists, the gate's STALE-INDEX finding names the
#    bare target, not the root-qualified one an area root would get.
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only STALE-INDEX | python3 -c '
import json, sys
d = json.load(sys.stdin)
targets = [f["target"] for f in d["findings"] if f["check"] == "STALE-INDEX"]
assert targets == ["INDEX.generated.md"], f"expected the bare target, got {targets}"
'
echo "OK: STALE-INDEX target is the bare, primary-only form"

# 2. build_index writes the bare header, not the root-qualified one an area
#    index carries.
python3 "$ROOT/scripts/build_index.py" --repo "$T" --write >/dev/null
HEADER="$(grep -m1 '^# INDEX' "$T/memory/INDEX.generated.md")"
[ "$HEADER" = "# INDEX (generated)" ] || { echo "FAIL: primary header carries a root suffix: $HEADER"; exit 1; }
echo "OK: primary index header is the bare, primary-only form"

# 3. The sweep never reports a second root: every scored, restamped,
#    declassified or emoji-flagged file traces back to the primary, and
#    nothing failed to parse along the way.
python3 "$ROOT/scripts/salience_sweep.py" --repo "$T" --as-of 2026-07-05 | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["errors"] == [], d["errors"]
groups = ("scores", "restamps", "declass_candidates", "emoji_suggestions")
roots = {item["root"] for g in groups for item in d[g]}
assert roots == {"memory"}, f"expected only the primary root, saw {roots}"
'
echo "OK: sweep sees exactly one root, the primary"

echo "OK: federation-off parity"
