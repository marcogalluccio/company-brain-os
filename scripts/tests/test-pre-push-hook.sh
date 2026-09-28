#!/usr/bin/env bash
# Tests for githooks/pre-push in a throwaway repo with a bare origin.
# The registry, the list and the identities are all invented fixtures.
set -u
ROOT="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pre-push-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail=0

git init -q --bare "$TMP/origin.git"
git init -q "$TMP/clone"
cd "$TMP/clone"
git remote add origin "$TMP/origin.git"
mkdir -p .github githooks scripts operators areas/finance areas/ops
cp -R "$ROOT/scripts/lib" scripts/lib
cp "$ROOT/githooks/pre-push" githooks/pre-push && chmod +x githooks/pre-push
git config core.hooksPath githooks
git config user.email "test@example.invalid"

cat > .github/sensitive-paths.txt <<'EOF'
!areas/finance/public-summary.md
areas/finance/*
EOF
printf -- '---\nslug: jane-doe\ngit_names:\n  - Jane Doe\ngithub: jane-doe\nsensitive_owner: true\n---\n' > operators/jane-doe.md
printf -- '---\nslug: sam-lee\ngit_names:\n  - Sam Lee\ngithub: sam-lee\n---\n' > operators/sam-lee.md

# Seed main as the owner.
git config user.name "Jane Doe"
echo seed > README.md
git add -A && git commit -qm "seed"
git push -q origin HEAD:main
git fetch -q origin

push_main()   { git push -q origin HEAD:main 2>"$TMP/hook.err"; }
reset_clean() { git reset -q --hard origin/main; }
# `git reset --hard` drops folders that became empty, so every write recreates its folder.
commit_file() { mkdir -p "$(dirname "$1")"; echo "$2" > "$1"; git add "$1"; git commit -qm "$1"; }

# 1. Non-owner, sensitive path, main: refused, with the reason.
git config user.name "Sam Lee"
commit_file areas/finance/budget.md x
if push_main; then echo "FAIL: non-owner sensitive push to main went through"; fail=1
else grep -q "PRE-PUSH REFUSED" "$TMP/hook.err" || { echo "FAIL: refusal reason missing"; fail=1; }; fi
reset_clean

# 2. Non-owner, plain path, main: passes.
commit_file areas/ops/runbook.md y
push_main || { echo "FAIL: non-owner plain push to main was refused"; fail=1; }

# 3. Non-owner, sensitive path, a proposal branch: passes (the hook only guards main).
commit_file areas/finance/forecast.md z
git push -q origin HEAD:refs/heads/sam-lee/proposals-test 2>/dev/null || { echo "FAIL: push to a proposal branch was refused"; fail=1; }
reset_clean

# 4. Owner, sensitive path, main: passes.
git config user.name "Jane Doe"
commit_file areas/finance/plan.md w
push_main || { echo "FAIL: owner sensitive push to main was refused"; fail=1; }

# 5. Non-owner, carve-out inside a sensitive folder, main: passes.
git config user.name "Sam Lee"
commit_file areas/finance/public-summary.md s
push_main || { echo "FAIL: carve-out push was refused"; fail=1; }

# 6. Unregistered identity, sensitive path, main: refused with IDENTITY ERROR.
git config user.name "Nobody Known"
commit_file areas/finance/notes.md n
if push_main; then echo "FAIL: unregistered identity pushed a sensitive path"; fail=1
else grep -q "IDENTITY ERROR" "$TMP/hook.err" || { echo "FAIL: identity error not reported"; fail=1; }; fi
reset_clean

# 7. Unregistered identity, plain path, main: passes (identity is only checked on a hit).
commit_file areas/ops/plain.md p
push_main || { echo "FAIL: unregistered identity was blocked on a plain path"; fail=1; }

# 8. A range this clone cannot diff: refused, not waved through. The hook is
# driven directly here, since git itself never hands it an unreachable sha.
git config user.name "Sam Lee"
UNREACHABLE=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
if printf 'refs/heads/main %s refs/heads/main %s\n' "$(git rev-parse HEAD)" "$UNREACHABLE" \
     | bash githooks/pre-push origin "$TMP/origin.git" 2>"$TMP/hook.err"; then
  echo "FAIL: a push that could not be scanned was allowed"; fail=1
else
  grep -q "PRE-PUSH REFUSED" "$TMP/hook.err" || { echo "FAIL: unscannable push refused without a reason"; fail=1; }
fi

# 9. Inert list: everything passes, even a non-owner on a sensitive path.
printf '# nothing active\n!areas/finance/public-summary.md\n' > .github/sensitive-paths.txt
git config user.name "Sam Lee"
commit_file areas/finance/inert.md i
push_main || { echo "FAIL: inert list still blocked a push"; fail=1; }

[ "$fail" = 0 ] && echo "OK: pre-push hook" || exit 1
