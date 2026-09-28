#!/usr/bin/env bash
# Malformed dates: a bad flag exits 2 with one line and no traceback; a bad date inside
# one file is reported in `errors` while the rest of the corpus is still processed.
set -eu
ROOT="$(git rev-parse --show-toplevel)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash "$ROOT/scripts/tests/fixtures/make_memory_fixture.sh" "$T" >/dev/null

set +e
python3 "$ROOT/scripts/memory_gate.py" --repo "$T" --as-of banana 2>"$T/err" >/dev/null; rc=$?
set -e
[ "$rc" = 2 ] || { echo "FAIL: gate --as-of banana rc=$rc (expected 2)"; exit 1; }
grep -q "is not valid" "$T/err" || { echo "FAIL: missing message"; cat "$T/err"; exit 1; }
if grep -q "Traceback" "$T/err"; then echo "FAIL: traceback exposed"; exit 1; fi
echo "OK: gate malformed as-of"

set +e
python3 "$ROOT/scripts/salience_sweep.py" --repo "$T" --as-of banana 2>"$T/err2" >/dev/null; rc=$?
set -e
[ "$rc" = 2 ] || { echo "FAIL: sweep --as-of banana rc=$rc (expected 2)"; exit 1; }
if grep -q "Traceback" "$T/err2"; then echo "FAIL: traceback exposed (sweep)"; exit 1; fi
echo "OK: sweep malformed as-of"

cat > "$T/memory/project_baddate.md" <<'EOF'
---
name: project_baddate
type: project
status: 🟡
last_touched: soon
salience: 0.5
---
EOF
python3 "$ROOT/scripts/salience_sweep.py" --repo "$T" --as-of 2026-07-05 | python3 -c '
import json, sys
d = json.load(sys.stdin)
errs = {e["file"] for e in d["errors"]}
assert errs == {"project_baddate.md"}, errs
files = {r["file"] for r in d["restamps"]}
assert "project_orphan.md" in files, files   # 65 days idle, 🟠: 0.15 - 0.20 -> 0.0 vs written 0.1
print("OK: sweep survives a malformed date")
'

# A file that is not valid UTF-8 at all (not merely a bad date inside otherwise
# readable frontmatter) must land in `errors` too, not crash the read that
# happens before frontmatter is even parsed. Write the invalid byte in binary
# mode: a shell heredoc can't carry a byte that isn't valid text in the first place.
python3 -c "
with open('$T/memory/project_badutf8.md', 'wb') as fh:
    fh.write(b'---\nname: project_badutf8\ntype: project\nstatus: \xff\xfe\nlast_touched: 2026-07-01\nsalience: 0.5\n---\n')
"
python3 "$ROOT/scripts/salience_sweep.py" --repo "$T" --as-of 2026-07-05 > "$T/out.json" 2>"$T/err3"; rc=$?
[ "$rc" = 0 ] || { echo "FAIL: sweep rc=$rc on a non-UTF-8 file (expected 0)"; cat "$T/err3"; exit 1; }
if grep -q "Traceback" "$T/err3"; then echo "FAIL: traceback exposed (non-UTF-8 file)"; exit 1; fi
python3 -c '
import json
d = json.load(open("'"$T"'/out.json", encoding="utf-8"))
errs = {e["file"] for e in d["errors"]}
assert "project_badutf8.md" in errs, errs
assert "project_baddate.md" in errs, errs   # the earlier bad-date file is still there and still reported
files = {r["file"] for r in d["restamps"]}
assert "project_orphan.md" in files, files   # the rest of the corpus is still scored despite the bad file
print("OK: sweep survives a non-UTF-8 file")
'
