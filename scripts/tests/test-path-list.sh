#!/usr/bin/env bash
# Tests for scripts/lib/path-list.sh: glob matching, exceptions that win
# regardless of their position, inert lists, unreadable lists.
set -u
ROOT="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/path-list-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail=0

. "$ROOT/scripts/lib/path-list.sh"

cat > "$TMP/list-a.txt" <<'EOF'
# a comment line
!skills/_improvements/friction-log.md
skills/*
CLAUDE.md
*/CLAUDE.md
docs/*
.github/*
areas/legal/*
EOF

# Exception written AFTER the pattern that would catch it: must still win.
cat > "$TMP/list-b.txt" <<'EOF'
areas/finance/*
!areas/finance/notes.md
EOF

# Only comments and exceptions: no active pattern.
cat > "$TMP/list-inert.txt" <<'EOF'
# nothing active
!areas/finance/notes.md
EOF

# Windows line endings must not break matching.
printf 'areas/ops/*\r\n!areas/ops/public.md\r\n' > "$TMP/list-crlf.txt"

expect_in()  { path_in_list "$1" "$2" || { echo "FAIL: '$2' should be listed in $(basename "$1")"; fail=1; }; }
expect_out() { path_in_list "$1" "$2" && { echo "FAIL: '$2' should NOT be listed in $(basename "$1")"; fail=1; }; }

expect_in  "$TMP/list-a.txt" "skills/ship/SKILL.md"
expect_in  "$TMP/list-a.txt" "skills/deep/nested/file.md"
expect_in  "$TMP/list-a.txt" "CLAUDE.md"
expect_in  "$TMP/list-a.txt" "memory/CLAUDE.md"
expect_in  "$TMP/list-a.txt" "areas/finance/CLAUDE.md"
expect_in  "$TMP/list-a.txt" "docs/GOVERNANCE.md"
expect_in  "$TMP/list-a.txt" ".github/workflows/sensitive-tripwire.yml"
expect_in  "$TMP/list-a.txt" "areas/legal/contract template.md"
expect_out "$TMP/list-a.txt" "skills/_improvements/friction-log.md"
expect_out "$TMP/list-a.txt" "memory/MEMORY.md"
expect_out "$TMP/list-a.txt" "daily-log/2026-01-01-jane-doe.md"
expect_out "$TMP/list-a.txt" "MYCLAUDE.md"
expect_out "$TMP/list-a.txt" "areas/legal-ops/x.md"

expect_in  "$TMP/list-b.txt" "areas/finance/budget.md"
expect_out "$TMP/list-b.txt" "areas/finance/notes.md"

expect_out "$TMP/list-inert.txt" "areas/finance/budget.md"
expect_out "$TMP/list-inert.txt" "areas/finance/notes.md"

expect_in  "$TMP/list-crlf.txt" "areas/ops/runbook.md"
expect_out "$TMP/list-crlf.txt" "areas/ops/public.md"

path_is_exception "$TMP/list-a.txt" "skills/_improvements/friction-log.md" || { echo "FAIL: friction-log should be an exception"; fail=1; }
path_is_exception "$TMP/list-a.txt" "skills/ship/SKILL.md" && { echo "FAIL: SKILL.md is not an exception"; fail=1; }

list_has_active_patterns "$TMP/list-a.txt" || { echo "FAIL: list-a has active patterns"; fail=1; }
list_has_active_patterns "$TMP/list-inert.txt" && { echo "FAIL: list-inert has no active pattern"; fail=1; }

path_in_list "$TMP/does-not-exist.txt" "CLAUDE.md"
[ "$?" = 2 ] || { echo "FAIL: unreadable list should exit 2"; fail=1; }

[ "$fail" = 0 ] && echo "OK: path-list" || exit 1
