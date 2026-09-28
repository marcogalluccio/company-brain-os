#!/usr/bin/env bash
# Adds a second memory root, areas/operations/memory/, to the fixture built by
# make_memory_fixture.sh. Usage: add_area_fixture.sh <target-dir>
set -eu
T="$1"
mkdir -p "$T/areas/operations/memory/archive"

node() { # node <relative path>; frontmatter + body on stdin
  cat > "$T/$1"
}

node areas/operations/memory/project_ops_one.md <<'EOF'
---
name: project_ops_one
type: project
status: 🟡
owner: operator-one
last_touched: 2026-07-02
salience: 0.5
---
## Status
Active.
## Next action
Assemble the thing with [[project_beta]].
EOF

node areas/operations/memory/project_ops_unlisted.md <<'EOF'
---
name: project_ops_unlisted
type: project
status: 🟡
owner: operator-one
last_touched: 2026-07-04
salience: 0.6
---
## Status
No row in the area index.
## Next action
Get an index row.
EOF

node areas/operations/memory/project_alpha.md <<'EOF'
---
name: project_alpha
type: project
status: 🟡
owner: operator-one
last_touched: 2026-07-01
salience: 0.6
---
## Status
Duplicate of the primary root's alpha.
## Next action
Should not exist here.
EOF

node areas/operations/memory/archive/project_ops_closed.md <<'EOF'
---
name: project_ops_closed
type: project
status: ❌
owner: operator-one
---
## Status
❌ Closed.
EOF

node areas/operations/memory/archive/INDEX.md <<'EOF'
# Archive

- [Ops Closed](project_ops_closed.md) - ❌ 2026-06-01, closed.
EOF

node areas/operations/memory/MEMORY.md <<'EOF'
# Memory: operations

## Projects

- [Ops One](project_ops_one.md) - 🟡 active. Folder: `areas/operations/one/`
- [Alpha](project_alpha.md) - 🟡 duplicate

## Archive

Closed items in [archive/INDEX.md](archive/INDEX.md).
EOF

cat >> "$T/memory/MEMORY.md" <<'EOF'

## Areas

- [Operations](../areas/operations/memory/MEMORY.md) - area memory for operations; open it when the session touches operations.
EOF

echo "area fixture ok: $T/areas/operations/memory"
