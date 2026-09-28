#!/usr/bin/env bash
# /session-debrief Step 0 decides where the daily log and memory get committed
# from one line: it compares the repository's own git directory with the
# common one, which differ only inside a linked worktree. If that line
# answered "no" inside a worktree, the debrief would commit the shared files
# onto the feature branch. This extracts the line from the skill and runs it
# in a plain repository (expects "no"), in a linked worktree on a feature
# branch (expects "yes"), and from a subfolder of each (the line must not
# depend on the current directory). Last, it runs the line under a stub git
# that rejects --path-format, as a git older than 2.31 does: the line must
# fail closed (expects "yes" in both trees, so the debrief stops and asks
# instead of taking the normal route inside a worktree).
set -u
ROOT="$(git rev-parse --show-toplevel)"
T="$(mktemp -d "${TMPDIR:-/tmp}/debrief-worktree-detect.XXXXXX")"
trap 'rm -rf "$T"' EXIT
fail=0

LINE="$(grep -E '^IN_WORKTREE=' "$ROOT/skills/session-debrief/SKILL.md" | head -1)"
[ -n "$LINE" ] || { echo "FAIL: Step 0 worktree detection line not found"; exit 1; }
printf '%s\necho "$IN_WORKTREE"\n' "$LINE" > "$T/detect.sh"

git init -q "$T/repo"
git -C "$T/repo" config user.email "test@example.invalid"
git -C "$T/repo" config user.name "Sam Lee"
mkdir -p "$T/repo/areas/ops"
echo seed > "$T/repo/areas/ops/notes.md"
git -C "$T/repo" add -A
git -C "$T/repo" commit -qm seed
git -C "$T/repo" worktree add -q "$T/wt" -b sam-lee/feature

check() { # label, dir, expected
  got="$(cd "$2" && PATH="${STUB_PATH:-$PATH}" bash "$T/detect.sh")"
  if [ "$got" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected $3, got $got"; fail=1; fi
}
check "main tree root" "$T/repo" no
check "main tree subfolder" "$T/repo/areas/ops" no
check "linked worktree root" "$T/wt" yes
check "linked worktree subfolder" "$T/wt/areas/ops" yes

REAL_GIT="$(command -v git)"
mkdir -p "$T/oldgit"
{
  printf '#!/usr/bin/env bash\n'
  printf 'for a in "$@"; do\n'
  printf '  case "$a" in --path-format*) echo "error: unknown option" >&2; exit 129 ;; esac\n'
  printf 'done\n'
  printf 'exec "%s" "$@"\n' "$REAL_GIT"
} > "$T/oldgit/git"
chmod +x "$T/oldgit/git"
STUB_PATH="$T/oldgit:$PATH"
check "old git, linked worktree (fails closed)" "$T/wt" yes
check "old git, main tree (fails closed)" "$T/repo" yes
unset STUB_PATH

[ "$fail" = 0 ] && echo "OK: debrief worktree detection" || exit 1
