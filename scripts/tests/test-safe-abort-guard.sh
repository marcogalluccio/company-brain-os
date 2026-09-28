#!/usr/bin/env bash
# The safe abort in skills/session-debrief/reference/push-outcomes.md (exit 20)
# is the only permitted way to abort a rebase stopped in the main tree. Its
# guard must exclude the conflicted paths (the abort is meant to reset those)
# and count every other unstaged change, because a bare `rebase --abort`
# would wipe it. The branch that runs the guard is only taken on a real
# conflict, so a guard that is wrong goes unnoticed until the day it matters.
# One classic mistake: filtering with a lowercase `--diff-filter=u` does not
# drop an unmerged path, which diff-files also reports as modified, so such a
# guard always sees "dirty" files and the abort can never run.
#
# This extracts the block from the reference, as written, and runs it in a
# throwaway repository with a rebase stopped on a real conflict over a path
# that contains a space:
#   1. conflict only: the guard reports nothing, the block aborts (exit 10);
#   2. conflict plus an unstaged edit to an unrelated tracked file: the guard
#      names exactly that file, the block stops (exit 30), the rebase and the
#      edit are both still there.
set -u
ROOT="$(git rev-parse --show-toplevel)"
REF="$ROOT/skills/session-debrief/reference/push-outcomes.md"
T="$(mktemp -d "${TMPDIR:-/tmp}/safe-abort-guard.XXXXXX")"
trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# The fenced block of the exit 20 section that holds the guard.
awk '/^## exit 20/{s=1; next}
     s && /^## /{exit}
     s && /^```bash$/{b=1; buf=""; next}
     s && b && /^```$/{b=0; if (index(buf, "comm -23")) {printf "%s", buf; exit} next}
     s && b {buf = buf $0 "\n"}' "$REF" > "$T/abort.sh"
[ -s "$T/abort.sh" ] || { echo "FAIL: safe abort block not found in the exit 20 section of $REF"; exit 1; }
GUARD="$(grep -E '^[[:space:]]*DIRTY=' "$T/abort.sh" | sed 's/^[[:space:]]*//')"
[ -n "$GUARD" ] || { echo "FAIL: guard line (DIRTY=...) not found in the safe abort block"; exit 1; }
printf '%s\nprintf "%%s" "$DIRTY"\n' "$GUARD" > "$T/guard.sh"

# A repository whose rebase stops on a conflict in "notes/meeting notes.md".
mk() {
  local d="$T/$1"
  git init -q "$d"
  cd "$d"
  git config user.email "test@example.invalid"; git config user.name "Sam Lee"
  git checkout -q -b main
  mkdir -p scripts notes
  cp "$ROOT/scripts/git-locked" scripts/git-locked; chmod +x scripts/git-locked
  printf 'base\n' > "notes/meeting notes.md"
  printf 'untouched\n' > notes/other.md
  git add -A; git commit -qm seed
  git checkout -q -b upstream
  printf 'upstream side\n' > "notes/meeting notes.md"; git commit -qam upstream
  git checkout -q main
  printf 'local side\n' > "notes/meeting notes.md"; git commit -qam local
  git rebase -q upstream >/dev/null 2>&1 && { echo "FAIL: setup rebase did not conflict"; exit 1; }
  git ls-files --unmerged | grep -q "meeting notes.md" || { echo "FAIL: setup has no unmerged path"; exit 1; }
}

in_rebase() { [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; }

# 1. Conflict only.
mk one
got="$(bash "$T/guard.sh")"
[ -z "$got" ] && ok "conflict only: guard reports nothing" || bad "conflict only: guard reported [$got]"
OUT="$(bash "$T/abort.sh" 2>&1)"; RC=$?
[ "$RC" = 10 ] && ! in_rebase && ok "conflict only: block aborts cleanly (exit 10)" || bad "conflict only: rc=$RC -- $OUT"

# 2. Conflict plus foreign unstaged work.
mk two
printf 'untouched\nforeign work\n' > notes/other.md
got="$(bash "$T/guard.sh")"
[ "$got" = "notes/other.md" ] && ok "foreign work: guard names exactly that file" || bad "foreign work: guard reported [$got]"
OUT="$(bash "$T/abort.sh" 2>&1)"; RC=$?
[ "$RC" = 30 ] && in_rebase && grep -q "foreign work" notes/other.md \
  && ok "foreign work: block stops (exit 30), rebase and work kept" || bad "foreign work: rc=$RC -- $OUT"

[ "$fail" = 0 ] && echo "OK: safe abort guard" || exit 1
