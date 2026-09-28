#!/usr/bin/env bash
set -eu
ROOT="$(git rev-parse --show-toplevel)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash "$ROOT/scripts/tests/fixtures/make_memory_fixture.sh" "$T" >/dev/null

# 1. A matching entry silences a warning; an entry with nothing to match is reported stale
cat > "$T/memory/memory-gate-allowlist.yml" <<'EOF'
- check: ORPHAN
  target: project_orphan.md
  reason: standalone item accepted in the test
- check: ORPHAN
  target: project_alpha.md
  reason: stale entry (alpha is not an orphan)
EOF
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only ORPHAN | python3 -c '
import json, sys
d = json.load(sys.stdin)
targets = {f["target"] for f in d["findings"]}
assert "project_orphan.md" not in targets, targets
assert "project_broken.md" in targets, targets
assert d["allowlisted"] == ["ORPHAN:project_orphan.md"], d["allowlisted"]
stale = d["stale_allowlist"]
assert len(stale) == 1 and stale[0]["target"] == "project_alpha.md", stale
print("OK: allowlist + stale")
'

# 2. An entry on a blocking finding never silences it
cat > "$T/memory/memory-gate-allowlist.yml" <<'EOF'
- check: BROKEN
  target: project_broken.md:ghost_target
  reason: attempt to silence a blocking finding
EOF
set +e
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only BROKEN --strict > "$T/b.json"; rc=$?
set -e
[ "$rc" = 1 ] || { echo "FAIL: --strict should still exit 1 (rc=$rc)"; exit 1; }
python3 -c '
import json
d = json.load(open("'"$T"'/b.json"))
assert any(f["check"] == "BROKEN" for f in d["findings"]), d["findings"]
assert d["invalid_allowlist"] == [{"check": "BROKEN", "target": "project_broken.md:ghost_target"}], d["invalid_allowlist"]
assert not d["green"]
print("OK: allowlist blocking guard")
'

# 3. ISLAND matches by subset: the island grows, the entry still covers it.
# A fourth node also joins the alpha/beta/gamma component in the same step, so
# the nucleus (4 nodes) is unambiguously larger than the growing island
# (3 nodes): which component wins a same-size tie is an implementation
# detail this suite must not depend on.
cat > "$T/memory/memory-gate-allowlist.yml" <<'EOF'
- check: ISLAND
  target: project_island_a,project_island_b
  reason: accepted island
EOF
cat > "$T/memory/project_island_c.md" <<'EOF'
---
name: project_island_c
type: project
status: 🟡
owner: operator-one
---
## Next action
See [[project_island_a]].
EOF
cat > "$T/memory/project_delta.md" <<'EOF'
---
name: project_delta
type: project
status: 🟡
owner: operator-one
---
## Next action
See [[project_alpha]].
EOF
printf -- '- [Delta](project_delta.md) - 🟡 joins the nucleus component\n' >> "$T/memory/MEMORY.md"
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only ISLAND | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["findings"] == [], d["findings"]
assert len(d["allowlisted"]) == 1, d["allowlisted"]
assert d["stale_allowlist"] == [], d["stale_allowlist"]
assert d["graph"]["nucleus_size"] == 4, d["graph"]  # alpha, beta, gamma, delta: unambiguous over the 3-node island
print("OK: allowlist island subset")
'
