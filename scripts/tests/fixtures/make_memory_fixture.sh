#!/usr/bin/env bash
# Synthetic memory corpus for the script tests. Usage: make_memory_fixture.sh <target-dir>
# Tests evaluate it with --as-of 2026-07-05. Every defect below is deliberate and
# named after the finding it should trigger; the operator slug is a placeholder.
set -eu
T="$1"
mkdir -p "$T/memory/archive" "$T/scripts" "$T/areas/clients"

node() { # node <relative path>; frontmatter + body on stdin
  cat > "$T/$1"
}

node memory/project_alpha.md <<'EOF'
---
name: project_alpha
type: project
status: 🟡
owner: operator-one
last_touched: 2026-07-01
salience: 0.6
---
## Status
Active.
## Next action
Close step A of the rollout.
## Updates
- 2026-07-01: moved forward, leans on [[strategic_gamma]].
EOF

node memory/project_beta.md <<'EOF'
---
name: project_beta
type: project
status: 🟢
owner: operator-one
last_touched: 2026-07-03
salience: 0.5
---
## Status
On track.
## Next action
Review with [[project_alpha]].
## Updates
- 2026-07-03: fine.
EOF

node memory/strategic_gamma.md <<'EOF'
---
name: strategic_gamma
type: strategic
status: 🟡
owner: operator-one
last_touched: 2026-06-20
salience: 0.3
---
## Position / Direction
Active direction.
## Updates
- 2026-06-20: confirmed, supports [[project_beta]].
EOF

node memory/project_island_a.md <<'EOF'
---
name: project_island_a
type: project
status: 🟡
owner: operator-one
last_touched: 2026-06-28
salience: 0.4
---
## Status
Active.
## Next action
Sync with [[project_island_b]].
EOF

node memory/project_island_b.md <<'EOF'
---
name: project_island_b
type: project
status: 🟡
owner: operator-one
last_touched: 2026-06-28
salience: 0.4
---
## Status
Active.
## Next action
See [[project_island_a]].
EOF

node memory/project_orphan.md <<'EOF'
---
name: project_orphan
type: project
status: 🟠
owner: operator-one
last_touched: 2026-05-01
salience: 0.1
---
## Status
Stalled.
## Next action
None.
EOF

node memory/project_broken.md <<'EOF'
---
name: project_broken
type: project
status: 🟡
owner: operator-one
last_touched: 2026-07-02
salience: 0.5
---
## Status
Active.
## Next action
See [[ghost_target]].
EOF

node memory/project_unlisted.md <<'EOF'
---
name: project_unlisted
type: project
status: 🟡
owner: operator-one
last_touched: 2026-07-04
salience: 0.6
---
## Status
Not indexed.
## Next action
Get an index row.
EOF

node memory/reference_standalone.md <<'EOF'
---
name: reference_standalone
type: reference
owner: operator-one
description: an external pointer
---
**Resource:** https://example.invalid/dashboard
EOF

node memory/feedback_note.md <<'EOF'
---
name: feedback_note
type: feedback
owner: operator-one
description: a working rule
---
**Rule:** Always show options before writing copy.
EOF

node memory/project_nested.md <<'EOF'
---
name: project_nested
metadata:
  type: project
---
## Status
Legacy nested schema, no top-level type.
EOF

node memory/archive/project_closed.md <<'EOF'
---
name: project_closed
type: project
status: ❌
owner: operator-one
---
## Status
❌ Closed.
EOF

node memory/MEMORY.md <<'EOF'
# Memory

## Projects

- [Alpha](project_alpha.md) - 🟢 active (wrong emoji on purpose). Folder: `areas/clients/alpha/`
- [Beta](project_beta.md) - 🟢 on track
- [Island A](project_island_a.md) - 🟡 island
- [Island B](project_island_b.md) - 🟡 island
- [Orphan](project_orphan.md) - 🟠 stalled
- [Broken](project_broken.md) - 🟡 broken link
- [Ghost](project_ghost.md) - 🟡 file does not exist

## Strategic

- [Gamma](strategic_gamma.md) - 🟡 direction

## References

- [Standalone](reference_standalone.md) - pointer

## Feedback

- [Note](feedback_note.md) - rule

## Archive

- [Closed](archive/project_closed.md) - ❌ closed 2026-06-01
EOF

echo "fixture ok: $T"
