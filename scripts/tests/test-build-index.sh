#!/usr/bin/env bash
set -eu
ROOT="$(git rev-parse --show-toplevel)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash "$ROOT/scripts/tests/fixtures/make_memory_fixture.sh" "$T" >/dev/null

# 1. Generate and check the content
python3 "$ROOT/scripts/build_index.py" --repo "$T" --write >/dev/null
IDX="$T/memory/INDEX.generated.md"
grep -q "DO NOT EDIT BY HAND" "$IDX"
grep -q "sources-hash:" "$IDX"
grep -q "project_alpha" "$IDX"
grep -q "Close step A of the rollout" "$IDX"      # next action from the ## Next action section
grep -q "areas/clients/alpha/" "$IDX"            # folder pointer inherited from the MEMORY.md row
grep -q "Archive: 1" "$IDX"
if grep -qE "20[0-9]{2}-[0-9]{2}-[0-9]{2}T" "$IDX"; then echo "FAIL: timestamp in the index"; exit 1; fi

# 2. Idempotent: a second run without changes produces identical bytes
cp "$IDX" "$T/first.md"
python3 "$ROOT/scripts/build_index.py" --repo "$T" --write >/dev/null
diff -q "$IDX" "$T/first.md" || { echo "FAIL: not idempotent"; exit 1; }

# 3. --check: 0 when fresh, 1 when a source changed
python3 "$ROOT/scripts/build_index.py" --repo "$T" --check || { echo "FAIL: --check on a fresh index"; exit 1; }
printf '\n## Next action\nChanged.\n' >> "$T/memory/project_beta.md"
set +e; python3 "$ROOT/scripts/build_index.py" --repo "$T" --check 2>/dev/null; rc=$?; set -e
[ "$rc" = 1 ] || { echo "FAIL: --check on a stale index should exit 1 (rc=$rc)"; exit 1; }

echo "OK: build-index"
