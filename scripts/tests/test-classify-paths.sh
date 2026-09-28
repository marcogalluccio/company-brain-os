#!/usr/bin/env bash
# Tests for scripts/classify-paths.sh: the four classes, their precedence,
# the sensitive-owner downgrade, exit codes, and missing lists (unadopted template behaviour).
set -u
ROOT="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/classify-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail=0

mkdir -p "$TMP/repo/scripts" "$TMP/repo/operators" "$TMP/lists"
cp -R "$ROOT/scripts/lib" "$TMP/repo/scripts/lib"
git -C "$TMP/repo" init -q

cat > "$TMP/lists/structural.txt" <<'EOF'
!skills/_improvements/friction-log.md
skills/*
scripts/*
CLAUDE.md
memory/CLAUDE.md
EOF
cat > "$TMP/lists/sensitive.txt" <<'EOF'
!areas/finance/public-summary.md
!skills/_improvements/friction-log.md
!areas/ops/exempt.md
areas/finance/*
skills/*
EOF
printf -- '---\nslug: jane-doe\ngit_names:\n  - Jane Doe\ngithub: jane-doe\nsensitive_owner: true\n---\n' > "$TMP/repo/operators/jane-doe.md"
printf -- '---\nslug: sam-lee\ngit_names:\n  - Sam Lee\ngithub: sam-lee\n---\n' > "$TMP/repo/operators/sam-lee.md"

export REPO_ROOT="$TMP/repo"
export STRUCTURAL_PATHS_FILE="$TMP/lists/structural.txt"
export SENSITIVE_PATHS_FILE="$TMP/lists/sensitive.txt"
export OPERATORS_DIR="$TMP/repo/operators"
CLASSIFY="$ROOT/scripts/classify-paths.sh"

expect_class() {
  # expect_class <expected-class> <path> [--operator <slug>]
  local want="$1" p="$2"; shift 2
  local got
  got="$(bash "$CLASSIFY" "$@" "$p" 2>/dev/null | awk -F'\t' '{print $1}')"
  [ "$got" = "$want" ] || { echo "FAIL: '$p' $* -> expected $want, got '$got'"; fail=1; }
}

expect_class structural "skills/ship/SKILL.md"
expect_class structural "skills/ship/SKILL.md" --operator jane-doe
expect_class structural "memory/CLAUDE.md"
expect_class structural "./scripts/x.sh"
# The carve-out class comes from an exception in either list, but a path only
# escapes structural and sensitive when every list whose patterns would catch
# it also exempts it, which is why the recommended seeds declare the
# friction-log exception in both.
expect_class carve-out  "skills/_improvements/friction-log.md"
expect_class carve-out  "areas/finance/public-summary.md"
# An exception line marks a carve-out even when its own list has no active
# pattern that would otherwise catch the path (here, no list has an
# areas/ops/* pattern): the class means "explicitly exempted somewhere", not
# "exempted from a match that would otherwise apply". Both carve-out and
# normal continue into the debrief the same way (main, exit 0), so this
# reading changes no routing decision; it only makes the intent of an
# exception line legible on its own, independent of what else is listed.
expect_class carve-out  "areas/ops/exempt.md"
expect_class normal     "areas/ops/other.md"
expect_class sensitive  "areas/finance/budget.md"
expect_class sensitive  "areas/finance/budget.md" --operator sam-lee
expect_class sensitive  "areas/finance/budget.md" --operator ghost
expect_class normal     "areas/finance/budget.md" --operator jane-doe
expect_class normal     "daily-log/2026-01-01-sam-lee.md"
expect_class normal     "areas/ops/CLAUDE.md"

# Output shape: class TAB path, one line per argument, order preserved.
out="$(bash "$CLASSIFY" "daily-log/a.md" "skills/x/SKILL.md" 2>/dev/null)"
[ "$out" = "$(printf 'normal\tdaily-log/a.md\nstructural\tskills/x/SKILL.md')" ] || { echo "FAIL: output shape: $out"; fail=1; }

# Header line on stderr when an operator is given.
hdr="$(bash "$CLASSIFY" --operator jane-doe "daily-log/a.md" 2>&1 >/dev/null)"
[ "$hdr" = "operator=jane-doe sensitive_owner=yes" ] || { echo "FAIL: header: $hdr"; fail=1; }
hdr="$(bash "$CLASSIFY" --operator sam-lee "daily-log/a.md" 2>&1 >/dev/null)"
[ "$hdr" = "operator=sam-lee sensitive_owner=no" ] || { echo "FAIL: header non-owner: $hdr"; fail=1; }

# Exit codes.
bash "$CLASSIFY" "daily-log/a.md" "skills/_improvements/friction-log.md" >/dev/null 2>&1; [ "$?" = 0 ] || { echo "FAIL: clean set should exit 0"; fail=1; }
bash "$CLASSIFY" "daily-log/a.md" "skills/x/SKILL.md" >/dev/null 2>&1; [ "$?" = 4 ] || { echo "FAIL: listed path should exit 4"; fail=1; }
bash "$CLASSIFY" --operator sam-lee "areas/finance/budget.md" >/dev/null 2>&1; [ "$?" = 4 ] || { echo "FAIL: sensitive for non-owner should exit 4"; fail=1; }
bash "$CLASSIFY" --operator jane-doe "areas/finance/budget.md" >/dev/null 2>&1; [ "$?" = 0 ] || { echo "FAIL: sensitive for owner should exit 0"; fail=1; }
bash "$CLASSIFY" >/dev/null 2>&1; [ "$?" = 64 ] || { echo "FAIL: no paths should exit 64"; fail=1; }

# Missing lists: everything normal, exit 0 (the template before adoption).
STRUCTURAL_PATHS_FILE="$TMP/none.txt" SENSITIVE_PATHS_FILE="$TMP/none.txt" \
  expect_class normal "skills/ship/SKILL.md"
STRUCTURAL_PATHS_FILE="$TMP/none.txt" SENSITIVE_PATHS_FILE="$TMP/none.txt" \
  bash "$CLASSIFY" "skills/ship/SKILL.md" >/dev/null 2>&1; [ "$?" = 0 ] || { echo "FAIL: missing lists should exit 0"; fail=1; }

[ "$fail" = 0 ] && echo "OK: classify-paths" || exit 1
