#!/usr/bin/env bash
# Index rows may live in MEMORY.md (inline layout) or in REFERENCES.md and
# archive/INDEX.md (split layout). Both must validate identically.
set -eu
ROOT="$(git rev-parse --show-toplevel)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash "$ROOT/scripts/tests/fixtures/make_memory_fixture.sh" "$T" >/dev/null

expect_rows() { # the INDEX-ROW findings the fixture is designed to produce, and nothing else
  python3 -c '
import json, sys
d = json.load(sys.stdin)
ids = {f["id"] for f in d["findings"] if f["check"] == "INDEX-ROW"}
assert ids == {"INDEX-ROW:project_ghost.md", "INDEX-ROW:project_unlisted.md", "INDEX-ROW:project_alpha.md",
              "INDEX-ROW:project_nested.md"}, ids   # nested: active, typeless, no row
untyped = {f["target"] for f in d["findings"] if f["check"] == "UNTYPED"}
assert untyped == {"project_nested.md"}, untyped          # REFERENCES.md and archive/INDEX.md are not nodes
print("OK:", sys.argv[1])
' "$1"
}

# 1. Inline layout (as the fixture ships)
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only INDEX-ROW,UNTYPED | expect_rows "inline layout"

# 2. Split layout: move the reference row and the archive row out of MEMORY.md
python3 - "$T" <<'EOF'
import sys
p = sys.argv[1] + "/memory/MEMORY.md"
t = open(p, encoding="utf-8").read()
t = t.replace("- [Standalone](reference_standalone.md) - pointer\n",
              "External pointers live in [REFERENCES.md](REFERENCES.md).\n")
t = t.replace("- [Closed](archive/project_closed.md) - ❌ closed 2026-06-01\n",
              "Closed items are listed in [archive/INDEX.md](archive/INDEX.md).\n")
open(p, "w", encoding="utf-8").write(t)
open(sys.argv[1] + "/memory/REFERENCES.md", "w", encoding="utf-8").write(
    "# References\n\n- [Standalone](reference_standalone.md) - pointer\n")
open(sys.argv[1] + "/memory/archive/INDEX.md", "w", encoding="utf-8").write(
    "# Archive\n\n- [Closed](project_closed.md) - ❌ closed 2026-06-01\n")
EOF
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only INDEX-ROW,UNTYPED | expect_rows "split layout"

# 3. A row in archive/INDEX.md pointing at a file that is not there is reported with the archive/ prefix
printf -- '- [Vanished](project_vanished.md) - ❌ closed 2026-01-01\n' >> "$T/memory/archive/INDEX.md"
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of 2026-07-05 --only INDEX-ROW | python3 -c '
import json, sys
d = json.load(sys.stdin)
ids = {f["id"] for f in d["findings"]}
assert "INDEX-ROW:archive/project_vanished.md" in ids, ids
print("OK: archive ghost row")
'

# 4. build_index: the archive count ignores archive/INDEX.md; REFERENCES.md is not a node
python3 "$ROOT/scripts/build_index.py" --repo "$T" --write >/dev/null
grep -q "Archive: 1 files" "$T/memory/INDEX.generated.md" || { echo "FAIL: archive/INDEX.md counted as an archived file"; exit 1; }
if grep -q '`REFERENCES`' "$T/memory/INDEX.generated.md"; then echo "FAIL: REFERENCES.md rendered as a node"; exit 1; fi
grep -q "reference_standalone" "$T/memory/INDEX.generated.md"
echo "OK: index split"
