#!/usr/bin/env bash
# Tests for scripts/lib/operator-registry.sh against an invented registry:
# resolution (one, zero, many matches), field reads, git_names bounded to
# their own list, the sensitive_owner flag, github login lookup, CLI dispatch.
set -u
ROOT="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/operator-registry-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail=0

mkdir -p "$TMP/operators/archive"
cat > "$TMP/operators/jane-doe.md" <<'EOF'
---
slug: jane-doe
git_names:
  - Jane Doe
  - jdoe
github: jane-doe
role: founder
sensitive_owner: true
---

## Machines

- laptop-01
EOF
cat > "$TMP/operators/sam-lee.md" <<'EOF'
---
slug: sam-lee
git_names:
  - Sam Lee
github: @SamLee
role: operations
extra_list:
  - not a git name
---

## Role

- a bullet in the body must not be read as a git name
EOF
# Non-registry files that always sit in operators/ and must be ignored.
printf '# operators\n' > "$TMP/operators/CLAUDE.md"
printf '# onboarding\n' > "$TMP/operators/ONBOARDING.md"
printf -- '---\nslug: <slug>\ngit_names:\n  - <name>\n---\n' > "$TMP/operators/operator_template.md"
# An archived operator lives below the registry, outside it.
printf -- '---\nslug: old-timer\ngit_names:\n  - Sam Lee\n---\n' > "$TMP/operators/archive/old-timer.md"

export OPERATORS_DIR="$TMP/operators"
. "$ROOT/scripts/lib/operator-registry.sh"

check_eq() { [ "$2" = "$3" ] || { echo "FAIL: $1: expected '$3', got '$2'"; fail=1; }; }

check_eq "registry_files count" "$(registry_files | wc -l | tr -d ' ')" "2"
check_eq "resolve Jane Doe" "$(resolve_operator "Jane Doe" 2>/dev/null)" "jane-doe"
check_eq "resolve jdoe" "$(resolve_operator "jdoe" 2>/dev/null)" "jane-doe"
check_eq "resolve Sam Lee (archive ignored)" "$(resolve_operator "Sam Lee" 2>/dev/null)" "sam-lee"
resolve_operator "Nobody" >/dev/null 2>"$TMP/err" && { echo "FAIL: unknown name should fail"; fail=1; }
grep -q "IDENTITY ERROR" "$TMP/err" || { echo "FAIL: unknown name should print IDENTITY ERROR"; fail=1; }
resolve_operator "" >/dev/null 2>"$TMP/err" && { echo "FAIL: empty name should fail"; fail=1; }
grep -q "is empty" "$TMP/err" || { echo "FAIL: empty name should say so"; fail=1; }

check_eq "field github" "$(operator_field jane-doe github)" "jane-doe"
check_eq "field role" "$(operator_field sam-lee role)" "operations"
check_eq "field absent" "$(operator_field sam-lee sensitive_owner)" ""
operator_field ghost github >/dev/null 2>&1 && { echo "FAIL: missing file should fail"; fail=1; }
check_eq "git_names jane" "$(operator_git_names jane-doe | tr '\n' '|')" "Jane Doe|jdoe|"
check_eq "git_names sam bounded" "$(operator_git_names sam-lee | tr '\n' '|')" "Sam Lee|"

is_sensitive_owner jane-doe || { echo "FAIL: jane-doe is a sensitive owner"; fail=1; }
is_sensitive_owner sam-lee && { echo "FAIL: sam-lee is not a sensitive owner"; fail=1; }
check_eq "sensitive owners" "$(sensitive_owner_slugs | tr '\n' '|')" "jane-doe|"
check_eq "slug for github (case, @)" "$(slug_for_github samlee)" "sam-lee"
check_eq "slug for github exact" "$(slug_for_github JANE-DOE)" "jane-doe"
slug_for_github nobody >/dev/null && { echo "FAIL: unknown login should fail"; fail=1; }

# Duplicate claim: two files with the same git_names entry must stop resolution.
printf -- '---\nslug: sam-two\ngit_names:\n  - Sam Lee\n---\n' > "$TMP/operators/sam-two.md"
resolve_operator "Sam Lee" >/dev/null 2>"$TMP/err" && { echo "FAIL: duplicate claim should fail"; fail=1; }
grep -q "matches 2" "$TMP/err" || { echo "FAIL: duplicate claim should report 2 matches"; fail=1; }
rm "$TMP/operators/sam-two.md"

# CLI dispatch (the skills call the script this way).
check_eq "cli resolve" "$(bash "$ROOT/scripts/lib/operator-registry.sh" resolve "Jane Doe" 2>/dev/null)" "jane-doe"
check_eq "cli field" "$(bash "$ROOT/scripts/lib/operator-registry.sh" field jane-doe github)" "jane-doe"
bash "$ROOT/scripts/lib/operator-registry.sh" is-sensitive-owner jane-doe || { echo "FAIL: cli is-sensitive-owner"; fail=1; }
check_eq "cli sensitive-owners" "$(bash "$ROOT/scripts/lib/operator-registry.sh" sensitive-owners)" "jane-doe"
check_eq "cli slug-for-github" "$(bash "$ROOT/scripts/lib/operator-registry.sh" slug-for-github samlee)" "sam-lee"
bash "$ROOT/scripts/lib/operator-registry.sh" bogus >/dev/null 2>&1
[ "$?" = 64 ] || { echo "FAIL: unknown cli command should exit 64"; fail=1; }

[ "$fail" = 0 ] && echo "OK: operator-registry" || exit 1
