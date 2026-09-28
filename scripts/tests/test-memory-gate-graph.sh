#!/usr/bin/env bash
# BROKEN, ORPHAN, ISLAND on the synthetic corpus.
set -eu
ROOT="$(git rev-parse --show-toplevel)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash "$ROOT/scripts/tests/fixtures/make_memory_fixture.sh" "$T" >/dev/null

python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 \
  --only BROKEN,ORPHAN,ISLAND | python3 -c '
import json, sys
d = json.load(sys.stdin)
ids = {f["id"] for f in d["findings"]}
assert "BROKEN:project_broken.md:ghost_target" in ids, ids
orphans = {f["target"] for f in d["findings"] if f["check"] == "ORPHAN"}
assert orphans == {"project_orphan.md", "project_broken.md", "project_unlisted.md"}, orphans
islands = [f for f in d["findings"] if f["check"] == "ISLAND"]
assert len(islands) == 1 and islands[0]["target"] == "project_island_a,project_island_b", islands
g = d["graph"]
assert g["nucleus_size"] == 3, g                      # alpha, beta, gamma
assert "reference_standalone" in g["no_incoming"], g  # in the graph, exempt as a finding
b = [f for f in d["findings"] if f["check"] == "BROKEN"][0]
assert b["severity"] == "error" and b["blocking"] is True, b
o = [f for f in d["findings"] if f["check"] == "ORPHAN"][0]
assert o["severity"] == "warning" and o["blocking"] is False, o
assert d["green"] is False
print("OK: memory-gate graph")
'
