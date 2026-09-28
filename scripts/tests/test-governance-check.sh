#!/usr/bin/env bash
# Tests for scripts/governance-check.sh: inert list, each finding in turn,
# then a fully coherent setup that must come out clean.
set -u
ROOT="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/governance-check-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail=0

git init -q "$TMP/repo"
cd "$TMP/repo"
mkdir -p .github/workflows scripts operators
cp -R "$ROOT/scripts/lib" scripts/lib
export REPO_ROOT="$TMP/repo"
CHECK="$ROOT/scripts/governance-check.sh"

expect_finding() { printf '%s\n' "$2" | grep -q "^FINDING: .*$1" || { echo "FAIL: expected a finding matching '$1', got:"; printf '%s\n' "$2"; fail=1; }; }
expect_no_finding() { printf '%s\n' "$2" | grep -q "^FINDING: .*$1" && { echo "FAIL: unexpected finding matching '$1'"; fail=1; }; }

# Inert list: exit 0, "inactive".
printf '# inert\n' > .github/sensitive-paths.txt
out="$(bash "$CHECK")"; rc=$?
[ "$rc" = 0 ] || { echo "FAIL: inert should exit 0"; fail=1; }
printf '%s' "$out" | grep -q "inactive" || { echo "FAIL: inert should say inactive: $out"; fail=1; }

# Active list, nothing else configured: every finding fires.
cat > .github/sensitive-paths.txt <<'EOF'
areas/finance/*
CLAUDE.md
EOF
printf -- '---\nslug: sam-lee\ngit_names:\n  - Sam Lee\ngithub: sam-lee\n---\n' > operators/sam-lee.md
out="$(bash "$CHECK")"; rc=$?
[ "$rc" = 1 ] || { echo "FAIL: findings should exit 1"; fail=1; }
expect_finding "sensitive_owner: true" "$out"
expect_finding "hooksPath" "$out"
expect_finding "sensitive-tripwire.yml" "$out"

# An owner without a github value.
printf -- '---\nslug: jane-doe\ngit_names:\n  - Jane Doe\nsensitive_owner: true\n---\n' > operators/jane-doe.md
out="$(bash "$CHECK")"
expect_no_finding "sensitive_owner: true" "$out"
expect_finding "without a github value" "$out"

# Fix the owner, activate the hook, add the workflow: only CODEOWNERS drift can remain.
printf -- '---\nslug: jane-doe\ngit_names:\n  - Jane Doe\ngithub: jane-doe\nsensitive_owner: true\n---\n' > operators/jane-doe.md
git config core.hooksPath githooks
printf 'name: sensitive-tripwire\n' > .github/workflows/sensitive-tripwire.yml
out="$(bash "$CHECK")"; rc=$?
[ "$rc" = 0 ] || { echo "FAIL: no CODEOWNERS should be clean, got: $out"; fail=1; }

# CODEOWNERS present but drifting both ways.
cat > .github/CODEOWNERS <<'EOF'
# routing map
/areas/finance/    @jane-doe
/areas/legal/      @jane-doe
/areas/ops/        @jane-doe @sam-lee
EOF
out="$(bash "$CHECK")"; rc=$?
[ "$rc" = 1 ] || { echo "FAIL: drift should exit 1"; fail=1; }
expect_finding "'CLAUDE.md' has no CODEOWNERS line" "$out"
expect_finding "routes 'areas/legal' only to sensitive owners" "$out"
expect_no_finding "areas/ops" "$out"
expect_no_finding "areas/finance" "$out"

# Coherent CODEOWNERS: clean.
cat > .github/CODEOWNERS <<'EOF'
/areas/finance/    @jane-doe
/areas/legal/      @jane-doe @sam-lee
/CLAUDE.md         @jane-doe
EOF
out="$(bash "$CHECK")"; rc=$?
[ "$rc" = 0 ] || { echo "FAIL: coherent setup should be clean, got: $out"; fail=1; }

[ "$fail" = 0 ] && echo "OK: governance-check" || exit 1
