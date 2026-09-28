#!/usr/bin/env bash
# Root discovery: memory/ plus areas/<name>/memory/MEMORY.md. With no area root the
# result is exactly ["memory"], which is what keeps every script on single-root behavior.
set -eu
ROOT="$(git rev-parse --show-toplevel)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash "$ROOT/scripts/tests/fixtures/make_memory_fixture.sh" "$T" >/dev/null

roots() {
  python3 - "$ROOT" "$T" <<'EOF'
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "scripts"))
import build_index
T = sys.argv[2]
print(" ".join(os.path.relpath(r, T) for r in build_index.memory_roots(T)))
EOF
}

# 1. Federation off: the primary root only
[ "$(roots)" = "memory" ] || { echo "FAIL: expected only memory/, got: $(roots)"; exit 1; }
echo "OK: roots off = primary only"

# 2. Wrong depth is not a root: a top-level <name>/memory/MEMORY.md is not under areas/
mkdir -p "$T/operations/memory" && printf '# stray\n' > "$T/operations/memory/MEMORY.md"
[ "$(roots)" = "memory" ] || { echo "FAIL: top-level folder treated as a root: $(roots)"; exit 1; }
echo "OK: top-level memory folder ignored"

# 3. A memory/ folder under areas/ without a MEMORY.md is not a root either
mkdir -p "$T/areas/clients/memory"
[ "$(roots)" = "memory" ] || { echo "FAIL: areas/clients/memory without MEMORY.md treated as a root"; exit 1; }
echo "OK: area folder without index ignored"

# 4. The real thing: areas/<name>/memory/MEMORY.md, primary first
bash "$ROOT/scripts/tests/fixtures/add_area_fixture.sh" "$T" >/dev/null
[ "$(roots)" = "memory areas/operations/memory" ] || { echo "FAIL: area root not found at areas/ depth: $(roots)"; exit 1; }
python3 - "$ROOT" "$T" <<'EOF'
import os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "scripts"))
import build_index
T = sys.argv[2]
assert build_index.is_primary(T, os.path.join(T, "memory"))
assert not build_index.is_primary(T, os.path.join(T, "areas", "operations", "memory"))
print("OK: is_primary")
EOF

# 5. build_index: one INDEX.generated.md per root; area nodes never leak into the primary
python3 "$ROOT/scripts/build_index.py" --repo "$T" --write >/dev/null
AREA_IDX="$T/areas/operations/memory/INDEX.generated.md"
test -f "$AREA_IDX" || { echo "FAIL: area index not generated"; exit 1; }
grep -q "project_ops_one" "$AREA_IDX"
grep -q "Archive: 1 files (areas/operations/memory/archive/)" "$AREA_IDX"
grep -q "^# INDEX (generated) - areas/operations/memory/$" "$AREA_IDX"
grep -q "^# INDEX (generated)$" "$T/memory/INDEX.generated.md" || { echo "FAIL: primary title changed"; exit 1; }
if grep -q "project_ops_one" "$T/memory/INDEX.generated.md"; then echo "FAIL: area node in the primary index"; exit 1; fi
python3 "$ROOT/scripts/build_index.py" --repo "$T" --check || { echo "FAIL: --check on fresh roots"; exit 1; }
printf '\n## Next action\nChanged.\n' >> "$T/areas/operations/memory/project_ops_one.md"
set +e; python3 "$ROOT/scripts/build_index.py" --repo "$T" --check 2>"$T/stale.txt"; rc=$?; set -e
[ "$rc" = 1 ] || { echo "FAIL: --check should exit 1 with a stale area index (rc=$rc)"; exit 1; }
grep -q "areas/operations/memory/INDEX.generated.md" "$T/stale.txt" || { echo "FAIL: stale root not named"; exit 1; }
echo "OK: build-index per root"

echo "OK: memory roots"
