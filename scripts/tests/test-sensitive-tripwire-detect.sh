#!/usr/bin/env bash
# Tests for scripts/sensitive-tripwire-detect.sh in a throwaway repo:
# hit by a non-owner, no hit by an owner, plain files, the identity anomaly,
# the first-push range, and the inert list.
set -u
ROOT="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tripwire-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail=0

git init -q "$TMP/repo"
cd "$TMP/repo"
mkdir -p .github scripts operators areas/finance areas/ops
cp -R "$ROOT/scripts/lib" scripts/lib
git config user.email "test@example.invalid"
cat > .github/sensitive-paths.txt <<'EOF'
areas/finance/*
EOF
printf -- '---\nslug: jane-doe\ngit_names:\n  - Jane Doe\ngithub: jane-doe\nsensitive_owner: true\n---\n' > operators/jane-doe.md
printf -- '---\nslug: sam-lee\ngit_names:\n  - Sam Lee\ngithub: sam-lee\n---\n' > operators/sam-lee.md

export REPO_ROOT="$TMP/repo"
DETECT="$ROOT/scripts/sensitive-tripwire-detect.sh"
ZERO=0000000000000000000000000000000000000000

git config user.name "Jane Doe"
git add -A && git commit -qm "seed"
SEED="$(git rev-parse HEAD)"

git config user.name "Sam Lee"
echo x > areas/finance/budget.md && git add areas/finance/budget.md && git commit -qm "budget"
A="$(git rev-parse HEAD)"
echo y > areas/ops/runbook.md && git add areas/ops/runbook.md && git commit -qm "runbook"
B="$(git rev-parse HEAD)"
git config user.name "Jane Doe"
echo z > areas/ops/plain.md && git add areas/ops/plain.md && git commit -qm "plain, authored as the owner"
C="$(git rev-parse HEAD)"

field() { sed -n "s/^$1=//p"; }
files() { sed -n '/^files:$/,$p' | tail -n +2; }

# Non-owner actor, sensitive file: hit.
r="$(bash "$DETECT" --before "$SEED" --after "$A" --actor sam-lee)"
[ "$(printf '%s' "$r" | field hit)" = "yes" ] || { echo "FAIL: non-owner hit expected: $r"; fail=1; }
[ "$(printf '%s' "$r" | files)" = "areas/finance/budget.md" ] || { echo "FAIL: hit file list: $r"; fail=1; }

# Owner actor, same range: no hit (files still reported for transparency).
r="$(bash "$DETECT" --before "$SEED" --after "$A" --actor JANE-DOE)"
[ "$(printf '%s' "$r" | field hit)" = "no" ] || { echo "FAIL: owner should not hit: $r"; fail=1; }

# Non-owner actor, plain file only: no hit.
r="$(bash "$DETECT" --before "$A" --after "$B" --actor sam-lee)"
[ "$(printf '%s' "$r" | field hit)" = "no" ] || { echo "FAIL: plain file should not hit: $r"; fail=1; }

# Non-owner actor pushing a commit authored under the owner's git identity: anomaly, hit.
r="$(bash "$DETECT" --before "$B" --after "$C" --actor sam-lee)"
[ "$(printf '%s' "$r" | field hit)" = "yes" ] || { echo "FAIL: anomaly should hit: $r"; fail=1; }
printf '%s' "$r" | field anomaly | grep -q "jane-doe" || { echo "FAIL: anomaly should name the owner slug: $r"; fail=1; }

# Owner actor pushing their own commit: no anomaly.
r="$(bash "$DETECT" --before "$B" --after "$C" --actor jane-doe)"
[ -z "$(printf '%s' "$r" | field anomaly)" ] || { echo "FAIL: owner should not raise an anomaly: $r"; fail=1; }

# First push (before = zero): the range falls back to the parent, then the empty tree.
r="$(bash "$DETECT" --before "$ZERO" --after "$A" --actor sam-lee)"
[ "$(printf '%s' "$r" | field hit)" = "yes" ] || { echo "FAIL: zero before should still scan: $r"; fail=1; }
r="$(bash "$DETECT" --before "" --after "$SEED" --actor jane-doe)"
[ "$(printf '%s' "$r" | field hit)" = "no" ] || { echo "FAIL: root commit scan: $r"; fail=1; }
# The same root commit pushed by a non-owner is the anomaly case: authored by the owner.
r="$(bash "$DETECT" --before "" --after "$SEED" --actor sam-lee)"
[ "$(printf '%s' "$r" | field hit)" = "yes" ] || { echo "FAIL: root commit by owner pushed by non-owner should hit: $r"; fail=1; }

# Unknown actor login: treated as a non-owner.
r="$(bash "$DETECT" --before "$SEED" --after "$A" --actor stranger)"
[ "$(printf '%s' "$r" | field hit)" = "yes" ] || { echo "FAIL: unknown actor should hit: $r"; fail=1; }

# A range this checkout cannot reach: the diff fails, so the scan never
# happened and must not be reported as a clean one. It surfaces as an anomaly
# naming the range, for an owner actor as much as for anyone else, and the
# exit contract is unchanged.
UNREACHABLE=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
r="$(bash "$DETECT" --before "$UNREACHABLE" --after "$A" --actor jane-doe 2>/dev/null)"
[ "$(printf '%s' "$r" | field hit)" = "yes" ] || { echo "FAIL: unreachable range reported as clean: $r"; fail=1; }
printf '%s' "$r" | field anomaly | grep -q "$UNREACHABLE" || { echo "FAIL: anomaly should name the unreachable range: $r"; fail=1; }
bash "$DETECT" --before "$UNREACHABLE" --after "$A" --actor jane-doe >/dev/null 2>&1
[ "$?" = 0 ] || { echo "FAIL: an unreachable range should still exit 0"; fail=1; }

# Inert list: never a hit.
printf '# inert\n' > .github/sensitive-paths.txt
r="$(bash "$DETECT" --before "$SEED" --after "$A" --actor sam-lee)"
[ "$(printf '%s' "$r" | field hit)" = "no" ] || { echo "FAIL: inert list should not hit: $r"; fail=1; }

# Usage.
bash "$DETECT" --after "$A" >/dev/null 2>&1; [ "$?" = 64 ] || { echo "FAIL: missing actor should exit 64"; fail=1; }

[ "$fail" = 0 ] && echo "OK: sensitive-tripwire-detect" || exit 1
