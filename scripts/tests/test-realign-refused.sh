#!/usr/bin/env bash
# "Realign refused" in skills/session-debrief/reference/push-outcomes.md is the
# way out when `git reset --keep origin/main` refuses to move a diverged local
# main. Its two blocks decide which uncommitted files may be set aside (only
# those already byte-identical to origin/main) and then move main. A block
# that released a file holding different content would destroy work, so this
# extracts both blocks from the reference and runs them, with the real
# scripts/git-locked, in throwaway clones:
#   A. blockers identical to origin (a modified tracked file, an untracked file
#      where origin adds one): listed RELEASABLE, released, main realigned,
#      bytes unchanged, unrelated work in progress untouched;
#   B. one blocker with content of its own: listed LIVE WORK, the release
#      block refuses (exit 30) and nothing moves;
#   C. a blocker whose working copy matches origin but whose staged version
#      does not match HEAD or origin: LIVE WORK too, staged content kept.
set -u
ROOT="$(git rev-parse --show-toplevel)"
REF="$ROOT/skills/session-debrief/reference/push-outcomes.md"
T="$(mktemp -d "${TMPDIR:-/tmp}/realign-refused.XXXXXX")"
trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# Fenced block inside "### Realign refused" whose text contains the marker.
extract() {
  awk -v marker="$1" '
    /^### Realign refused/ {s=1; next}
    s && /^##/ {exit}
    s && /^[[:space:]]*```bash[[:space:]]*$/ {b=1; buf=""; next}
    s && b && /^[[:space:]]*```[[:space:]]*$/ {b=0; if (index(buf, marker)) {printf "%s", buf; exit} next}
    s && b {buf = buf $0 "\n"}' "$REF"
}
extract "NO BLOCKER: nothing in the tree" > "$T/list.sh"
extract "REALIGNED:" > "$T/release.sh"
[ -s "$T/list.sh" ] || { echo "FAIL: listing block not found in $REF"; exit 1; }
[ -s "$T/release.sh" ] || { echo "FAIL: release block not found in $REF"; exit 1; }

# origin + two clones. A holds a local commit whose content reached origin
# under another hash (the state a temporary-worktree push leaves behind);
# B pushes that content plus more.
mk() {
  local d="$T/$1"
  git init -q --bare "$d/origin.git"
  git -C "$d/origin.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$d/origin.git" "$d/A" 2>/dev/null
  cd "$d/A"
  git config user.email "test@example.invalid"; git config user.name "Sam Lee"
  git checkout -q -b main
  mkdir -p scripts areas/notes
  cp "$ROOT/scripts/git-locked" scripts/git-locked; chmod +x scripts/git-locked
  printf 'one\n' > areas/notes/shared.md
  printf 'two\n' > areas/notes/other.md
  printf 'wip base\n' > areas/notes/wip.md
  git add -A; git commit -qm seed; git push -q origin main
  git clone -q "$d/origin.git" "$d/B" 2>/dev/null
  git -C "$d/B" config user.email "b@example.invalid"; git -C "$d/B" config user.name "Pat Roe"
  printf 'one\nsession line\n' > "$d/B/areas/notes/shared.md"
  printf 'two\nfrom origin\n' > "$d/B/areas/notes/other.md"
  printf 'added on origin\n' > "$d/B/areas/notes/added.md"
  git -C "$d/B" add -A; git -C "$d/B" commit -qm "same content, other hash"; git -C "$d/B" push -q origin main
  printf 'one\nsession line\n' > areas/notes/shared.md
  git commit -qam "session commit"
  git fetch -q origin
}

# ---- A: every blocker identical to origin
mk a; D="$T/a"; cd "$D/A"
printf 'two\nfrom origin\n' > areas/notes/other.md          # tracked, dirty, identical to origin
printf 'added on origin\n' > areas/notes/added.md          # untracked, identical to what origin adds
printf 'wip base\nmine\n' > areas/notes/wip.md             # unrelated work in progress
git reset -q --keep origin/main 2>/dev/null && bad "A: setup did not block the reset" || ok "A: plain reset --keep refuses"
OUT="$(bash "$T/list.sh" 2>&1)"
echo "$OUT" | grep -qx "RELEASABLE: areas/notes/other.md" && echo "$OUT" | grep -qx "RELEASABLE: areas/notes/added.md" \
  && echo "$OUT" | grep -qx "ALL RELEASABLE" && ! echo "$OUT" | grep -q "wip.md" \
  && ok "A: listing names both blockers as releasable, not the unrelated file" || bad "A: listing -- $OUT"
OUT="$(bash "$T/release.sh" 2>&1)"; RC=$?
[ "$RC" = 0 ] && echo "$OUT" | grep -q "^REALIGNED:" && ok "A: release realigned" || bad "A: release rc=$RC -- $OUT"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && ok "A: local main on origin/main" || bad "A: main not moved"
[ "$(cat areas/notes/other.md)" = "$(printf 'two\nfrom origin')" ] && [ "$(cat areas/notes/added.md)" = "added on origin" ] \
  && ok "A: released files unchanged" || bad "A: released files changed"
[ "$(cat areas/notes/wip.md)" = "$(printf 'wip base\nmine')" ] && ok "A: unrelated work in progress kept" || bad "A: work in progress lost"

# ---- B: one blocker holds its own content
mk b; D="$T/b"; cd "$D/A"
printf 'two\nfrom origin\n' > areas/notes/other.md
printf 'my own draft\n' > areas/notes/added.md             # differs from what origin adds
HEAD_BEFORE="$(git rev-parse HEAD)"
OUT="$(bash "$T/list.sh" 2>&1)"
echo "$OUT" | grep -qx "LIVE WORK: areas/notes/added.md" && echo "$OUT" | grep -qx "LIVE WORK PRESENT: release nothing" \
  && ok "B: listing names the live file" || bad "B: listing -- $OUT"
OUT="$(bash "$T/release.sh" 2>&1)"; RC=$?
[ "$RC" = 30 ] && ok "B: release refuses with exit 30" || bad "B: release rc=$RC -- $OUT"
[ "$(git rev-parse HEAD)" = "$HEAD_BEFORE" ] && [ "$(cat areas/notes/added.md)" = "my own draft" ] \
  && [ "$(cat areas/notes/other.md)" = "$(printf 'two\nfrom origin')" ] \
  && ok "B: nothing moved, nothing released" || bad "B: tree or main changed"

# ---- C: working copy matches origin, but a staged version holds content of its own
mk c; D="$T/c"; cd "$D/A"
printf 'two\nstaged draft\n' > areas/notes/other.md
git add areas/notes/other.md
printf 'two\nfrom origin\n' > areas/notes/other.md       # working copy back to origin's content
STAGED_BEFORE="$(git ls-files -s -- areas/notes/other.md | cut -d" " -f2)"
HEAD_BEFORE="$(git rev-parse HEAD)"
OUT="$(bash "$T/list.sh" 2>&1)"
echo "$OUT" | grep -qx "LIVE WORK: areas/notes/other.md" && ok "C: listing names the partially staged file as live" || bad "C: listing -- $OUT"
OUT="$(bash "$T/release.sh" 2>&1)"; RC=$?
[ "$RC" = 30 ] && ok "C: release refuses with exit 30" || bad "C: release rc=$RC -- $OUT"
[ "$(git rev-parse HEAD)" = "$HEAD_BEFORE" ] && [ "$(git ls-files -s -- areas/notes/other.md | cut -d" " -f2)" = "$STAGED_BEFORE" ] \
  && ok "C: staged content and main intact" || bad "C: staged content or main changed"

[ "$fail" = 0 ] && echo "OK: realign refused procedure" || exit 1
