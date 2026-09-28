#!/usr/bin/env bash
# The sweep applies the formula of docs/ADVANCED.md section 3 to a small corpus with
# one file per branch of the formula. Expected scores are worked out in the comments.
set -eu
ROOT="$(git rev-parse --show-toplevel)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/memory/archive" "$T/areas/ops/memory"
mknode() { cat > "$T/memory/$1"; }

# 4 days idle: recency 0.30 + 🟢 0.20 = 0.50 = written, no restamp
mknode project_steady.md <<'EOF'
---
name: project_steady
type: project
status: 🟢
last_touched: 2026-07-01
salience: 0.5
---
EOF
# 46 days idle: recency 0 + 🟡 0.25 - decay 0.10 = 0.15 -> 0.2; written 0.6 -> restamp, declass
mknode project_cooling.md <<'EOF'
---
name: project_cooling
type: project
status: 🟡
last_touched: 2026-05-20
salience: 0.6
---
EOF
# 45 days idle, 🟡, 0.2 = written: no restamp, but cold enough for an emoji suggestion
mknode project_cold_emoji.md <<'EOF'
---
name: project_cold_emoji
type: project
status: 🟡
last_touched: 2026-05-21
salience: 0.2
---
EOF
# deadline in 3 days: 0.30 + 0.40 + 🔴 0.30 = 1.00 (clamped) = written
mknode project_deadline.md <<'EOF'
---
name: project_deadline
type: project
status: 🔴
last_touched: 2026-07-04
deadline: 2026-07-08
salience: 1.0
---
EOF
# overdue by 3 days keeps full proximity: 0.30 + 0.40 + 0.25 = 0.95 -> 1.0 = written
mknode project_overdue_fresh.md <<'EOF'
---
name: project_overdue_fresh
type: project
status: 🟡
last_touched: 2026-07-04
deadline: 2026-07-02
salience: 1.0
---
EOF
# overdue by 15 days loses proximity: 0.30 + 0 + 0.25 = 0.55 -> 0.6; written 1.0 -> restamp, declass
mknode project_overdue_old.md <<'EOF'
---
name: project_overdue_old
type: project
status: 🟡
last_touched: 2026-07-04
deadline: 2026-06-20
salience: 1.0
---
EOF
# 126 days idle, pinned: 0 + 🟠 0.15 + 0.40 - decay 0.40 = 0.15 -> 0.2; written 0.5 -> restamp
mknode project_pinned.md <<'EOF'
---
name: project_pinned
type: project
status: 🟠
last_touched: 2026-03-01
pinned: true
salience: 0.5
---
EOF
# upward drift: 4 days idle, 🟢 -> 0.30 + 0.20 = 0.50 computed vs 0.3 written.
# Proves the declass filter is direction-sensitive (computed < written only):
# a drift where computed is HIGHER than written must restamp but never declass.
mknode project_warming.md <<'EOF'
---
name: project_warming
type: project
status: 🟢
last_touched: 2026-07-01
salience: 0.3
---
EOF
# no salience field: scored, never a restamp (nothing written to drift from)
mknode project_unscored.md <<'EOF'
---
name: project_unscored
type: project
status: 🟡
last_touched: 2026-07-01
---
EOF
# reference: exempt by type
mknode reference_pointer.md <<'EOF'
---
name: reference_pointer
type: reference
description: exempt
---
EOF
# an area root: swept too, with its root named
printf '# Memory: ops\n' > "$T/areas/ops/memory/MEMORY.md"
cat > "$T/areas/ops/memory/project_ops.md" <<'EOF'
---
name: project_ops
type: project
status: 🟢
last_touched: 2026-07-03
salience: 0.5
---
EOF
printf '# Memory\n' > "$T/memory/MEMORY.md"

python3 "$ROOT/scripts/salience_sweep.py" --repo "$T" --as-of 2026-07-05 | python3 -c '
import json, sys
d = json.load(sys.stdin)
scores = {s["file"]: s for s in d["scores"]}
assert scores["project_steady.md"]["computed"] == 0.5, scores
assert scores["project_unscored.md"]["written"] is None, scores
assert scores["project_ops.md"]["root"] == "areas/ops/memory", scores
assert "reference_pointer.md" not in scores, scores
re_ = {r["file"]: r for r in d["restamps"]}
# project_warming.md joins the restamp set alongside the three downward-drift
# fixtures below: it drifts UPWARD (computed 0.5 > written 0.3), so it belongs
# in restamps but, per the assertions further down, must never reach declass.
assert set(re_) == {"project_cooling.md", "project_overdue_old.md", "project_pinned.md",
                     "project_warming.md"}, re_
assert re_["project_cooling.md"]["computed"] == 0.2 and re_["project_cooling.md"]["written"] == 0.6, re_
assert re_["project_overdue_old.md"]["computed"] == 0.6, re_
assert re_["project_pinned.md"]["computed"] == 0.2, re_
assert re_["project_warming.md"]["computed"] == 0.5 and re_["project_warming.md"]["written"] == 0.3, re_
dc = {r["file"] for r in d["declass_candidates"]}
# Unchanged from the original three: proves the "computed < written" direction
# filter is real, not a no-op, because project_warming.md (computed > written)
# is in restamps above but absent here.
assert dc == {"project_cooling.md", "project_overdue_old.md", "project_pinned.md"}, dc
assert "project_warming.md" not in dc, dc
em = {e["file"] for e in d["emoji_suggestions"]}
assert "project_cold_emoji.md" in em and "project_deadline.md" not in em, em
assert d["errors"] == [], d["errors"]
print("OK: salience sweep")
'
