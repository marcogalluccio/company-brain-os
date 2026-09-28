#!/usr/bin/env bash
# /session-debrief Step 4 turns `git status --short` into arguments for
# scripts/classify-paths.sh through a shell pipeline written inline in the
# skill: rename-arrow removal, then quote stripping, then a NUL-separated
# xargs. Nothing else drives that pipeline (test-classify-paths.sh calls the
# classifier directly, test-skill-snippets.sh only reads the file), so a
# reflow of the block could regress without a test noticing.
#
# This extracts the block from the skill and runs it in a throwaway repo whose
# working tree carries the two shapes the stages exist for: a path with a
# space in a listed folder, which git status wraps in literal double quotes,
# and a rename whose new name contains a space, which arrives as
# `old -> "new name"` and needs the arrow removed before the quotes.
set -u
ROOT="$(git rev-parse --show-toplevel)"
T="$(mktemp -d "${TMPDIR:-/tmp}/debrief-classify-block.XXXXXX")"
trap 'rm -rf "$T"' EXIT
fail=0

awk '/^## Step 4: Detect content work/{s=1}
     s && /^## Step 5/{exit}
     s && /^```bash$/{b=1; buf=""; next}
     b && /^```$/{b=0; if (index(buf, "classify-paths.sh")) {printf "%s", buf; exit} next}
     b {buf = buf $0 "\n"}' \
  "$ROOT/skills/session-debrief/SKILL.md" > "$T/block.sh"
[ -s "$T/block.sh" ] || { echo "FAIL: Step 4 classify block not found"; exit 1; }
if grep -qE '\$[0-9]' "$T/block.sh"; then echo "FAIL: positional parameter in a skill snippet"; exit 1; fi
# The block carries the slug as literal text for the agent to substitute.
grep -q '<slug-from-step-0>' "$T/block.sh" || { echo "FAIL: block no longer carries the slug placeholder"; exit 1; }
sed 's/<slug-from-step-0>/sam-lee/' "$T/block.sh" > "$T/run.sh"

# The throwaway repo the block runs in.
git init -q "$T/repo"
cd "$T/repo"
git config user.email "test@example.invalid"
git config user.name "Sam Lee"
mkdir -p .github scripts operators areas/ops areas/finance "skills/my skill"
cp "$ROOT/scripts/classify-paths.sh" scripts/classify-paths.sh
chmod +x scripts/classify-paths.sh
cp -R "$ROOT/scripts/lib" scripts/lib
printf 'skills/*\n' > .github/structural-paths.txt
printf 'areas/finance/*\n' > .github/sensitive-paths.txt
printf -- '---\nslug: sam-lee\ngit_names:\n  - Sam Lee\ngithub: sam-lee\n---\n' > operators/sam-lee.md
echo old > areas/ops/old.md
git add -A && git commit -qm "seed"

# A rename whose new name has a space, and lands in a listed folder so that a
# surviving quote would change the class rather than only the printed path.
git mv areas/ops/old.md "areas/finance/new name.md"
echo p > areas/ops/plain.md
echo q > "areas/finance/q with space.md"
echo s > "skills/my skill/SKILL.md"

status="$(git -c core.quotePath=false status --short --untracked-files=all)"
printf '%s\n' "$status" | grep -q ' -> "areas/finance/new name.md"' \
  || { echo "FAIL: fixture did not produce a quoted rename target"; printf '%s\n' "$status"; exit 1; }

bash "$T/run.sh" > "$T/out.txt" 2> "$T/err.txt" || true

expect_line() {
  grep -qxF "$(printf '%s\t%s' "$1" "$2")" "$T/out.txt" \
    || { echo "FAIL: expected class '$1' for '$2'"; cat "$T/out.txt"; fail=1; }
}

expect_line sensitive  "areas/finance/new name.md"
expect_line structural "skills/my skill/SKILL.md"
expect_line sensitive  "areas/finance/q with space.md"
expect_line normal     "areas/ops/plain.md"

# The old name of a rename is not classified: only the new one is.
if grep -q "areas/ops/old.md" "$T/out.txt"; then echo "FAIL: the pre-rename path reached the classifier"; cat "$T/out.txt"; fail=1; fi
# No path reaches the classifier still wrapped in the quotes git status adds.
if grep -q '"' "$T/out.txt"; then echo "FAIL: a quoted path survived the pipeline"; cat "$T/out.txt"; fail=1; fi
[ "$(wc -l < "$T/out.txt" | tr -d ' ')" = 4 ] || { echo "FAIL: expected four classified paths"; cat "$T/out.txt"; fail=1; }
# The operator is passed through to the classifier, which is what makes the
# sensitive class possible at all.
grep -q "^operator=sam-lee sensitive_owner=no$" "$T/err.txt" \
  || { echo "FAIL: operator header missing from stderr"; cat "$T/err.txt"; fail=1; }

[ "$fail" = 0 ] && echo "OK: session-debrief step 4 classify block" || exit 1
