#!/usr/bin/env bash
# Debrief push engine: stage the session's files, commit, integrate with
# origin/main, push, and verify by content that the work reached origin.
#
# Usage:
#   scripts/git-locked scripts/debrief-push.sh <file>...
#   scripts/git-locked scripts/debrief-push.sh --integrate-only
#
# Every argument is one file to commit, quoted. Directories are refused: a
# blanket add would sweep in work this session did not write. With
# --integrate-only nothing is staged or committed; the local commits that
# origin does not have yet are integrated and pushed (the /sync path).
#
# The main working tree is never rebased while it holds uncommitted work: in
# that case the integration runs in a temporary worktree and the main tree is
# left untouched. A conflict inside that worktree is left standing for a human
# to resolve there (exit 21); it is never aborted behind their back.
#
# Exit codes are documented in skills/session-debrief/reference/push-outcomes.md
# and change there and here in the same commit. On any exit other than 0 the
# path of that file is printed, so the caller reads the procedure instead of
# improvising.
#
# Team options, read from git config on this clone (default false):
#   brain.debrief.autoTake   resolve a conflicted daily-log/ or memory/ file by
#                            taking origin when the local side is a strict
#                            subset of it (no line lost); declared in the output
#   brain.debrief.realign    after a push through the temporary worktree, move
#                            local main to origin/main with reset --keep
set -e
REF="skills/session-debrief/reference/push-outcomes.md"
trap 'rc=$?; [ "$rc" -eq 0 ] || echo "exit $rc: procedure in $REF"' EXIT
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$(git rev-parse --show-toplevel)"

MODE=commit
if [ "$#" -ge 1 ] && [ "$1" = "--integrate-only" ]; then
  MODE=integrate; shift
fi
if [ "$MODE" = commit ]; then
  if [ "$#" -lt 1 ]; then
    echo "USAGE: scripts/debrief-push.sh <file>... | --integrate-only"
    echo "No file received: nothing was committed."
    exit 64
  fi
  for p in "$@"; do
    if [ -d "$p" ]; then
      echo "USAGE: \"$p\" is a directory; pass files one by one. Nothing was committed."
      exit 64
    fi
    # A path is acceptable if it is on disk, in the index, or was tracked at
    # HEAD (the old name of a staged rename, or a deletion to record).
    if [ ! -e "$p" ] && ! git ls-files --error-unmatch -- "$p" >/dev/null 2>&1 \
       && ! git cat-file -e "HEAD:$p" 2>/dev/null; then
      echo "USAGE: \"$p\" is not on disk, not in the index and not tracked at HEAD. Nothing was committed."
      exit 64
    fi
  done
elif [ "$#" -gt 0 ]; then
  echo "USAGE: --integrate-only takes no file arguments; got: $*"
  echo "Nothing was committed or pushed."
  exit 64
fi
ALLOW=("$@")

[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "GUARD: HEAD is not on main; nothing was committed"; exit 3; }
# Merge and rebase state lives in this worktree's git dir. Only the state
# directories are reliable: REBASE_HEAD can outlive a finished rebase.
GD="$(git rev-parse --absolute-git-dir)"
if [ -e "$GD/MERGE_HEAD" ] || [ -d "$GD/rebase-merge" ] || [ -d "$GD/rebase-apply" ]; then
  echo "PRE-FLIGHT FAIL: a merge or rebase is already in progress; nothing was committed"; exit 2
fi

AUTO_TAKE="$(git config --bool brain.debrief.autoTake 2>/dev/null || echo false)"
REALIGN="$(git config --bool brain.debrief.realign 2>/dev/null || echo false)"

# The operator slug comes from the registry, never from the git name itself:
# exactly one operators/<slug>.md must list this git user.name in git_names.
# Sets SLUG; returns 1 (with the reason printed) when the rule is not met.
resolve_slug() {
  local name matches n f
  name="$(git config user.name)"
  [ -n "$name" ] || { echo "IDENTITY ERROR: git config user.name is empty; nothing was committed"; return 1; }
  matches=""
  for f in operators/*.md; do
    case "$f" in operators/CLAUDE.md|operators/ONBOARDING.md|operators/operator_template.md) continue ;; esac
    [ -f "$f" ] || continue
    if awk '/^---$/{if(f)exit;f=1;next} f' "$f" | sed 's/^[[:space:]]*//' | grep -qxF -- "- $name"; then
      matches="$matches $f"
    fi
  done
  n="$(echo $matches | wc -w | tr -d ' ')"
  [ "$n" = 1 ] || { echo "IDENTITY ERROR: git user.name \"$name\" matches $n operator files:$matches; nothing was committed"; return 1; }
  SLUG="$(basename $matches .md)"
}
if [ "$MODE" = commit ]; then
  # Whatever is already staged rides into the commit. Stop if any of it is
  # outside the allow-list: it is another session's work, and the choice of
  # what to do with it is a human one. --no-renames so both halves of a
  # staged rename are listed and compared.
  STAGED_ALL="$(git diff --cached --no-renames --name-only | LC_ALL=C sort)"
  STAGED_IN="$(git diff --cached --no-renames --name-only -- "${ALLOW[@]}" | LC_ALL=C sort)"
  if [ "$STAGED_ALL" != "$STAGED_IN" ]; then
    echo "GUARD-INDEX: the index already holds staged paths outside the allow-list:"
    comm -23 <(printf "%s\n" "$STAGED_ALL") <(printf "%s\n" "$STAGED_IN")
    echo "A plain commit would sweep them in. Nothing was committed; the staged content is intact."
    exit 4
  fi
  resolve_slug || exit 65
  for p in "${ALLOW[@]}"; do
    # The old name of a staged rename is neither on disk nor in the index:
    # its removal is already staged, so there is nothing left to add.
    if [ -e "$p" ] || git ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
      git add -- "$p"
    fi
  done
  if git diff --cached --quiet; then
    echo "USAGE: none of the listed files has changes to commit. Nothing was committed."
    exit 64
  fi
  git commit -q -m "debrief: $(date +%Y-%m-%d) $(date +%H%M) ($SLUG)"
  TO="$(git rev-parse HEAD)"
  echo "session commit: $TO"
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "LOCAL-ONLY: no origin remote configured; commit kept locally"; exit 0
fi
# A remote that cannot be reached is an ordinary outcome, not an anomaly: the
# commit is already made and stays where it is. It gets its own code so the
# caller reads a procedure instead of git's raw exit status.
git fetch origin main --quiet || { echo "FETCH FAILED: could not reach origin; commit kept locally"; exit 50; }

# The verified range starts at the fork point, not at the session commit's
# parent. Commits an earlier run left behind, and any content commit made
# before this one, ride the same push; a commit that goes out unverified is
# exactly what this check exists to prevent.
if [ "$MODE" = integrate ]; then
  TO="$(git rev-parse HEAD)"
fi
FROM="$(git merge-base HEAD origin/main)"
if [ "$MODE" = integrate ] && [ "$FROM" = "$TO" ]; then
  echo "NOTHING-TO-INTEGRATE: origin/main already contains every local commit"; exit 0
fi

# The push's exit code says nothing about content: a rebase can drop a commit
# on the way and the push still succeeds. Every line added or removed between
# FROM and TO must be reflected on origin/main after the push. No file filter:
# the index guard already keeps the session commit inside the allow-list, so
# filtering would narrow nothing there and would hide the earlier commits the
# same push carries.
verify_pushed() {
  "$SCRIPT_DIR/debrief-verify.sh" "$FROM" "$TO" "${PUSHED_HEAD:--}"
}

# After a push through the temporary worktree, local main still points at the
# pre-rebase commits. Their content is on origin (just verified) but not
# their patch identity, so a later rebase would not drop them as duplicates:
# it would replay them as spurious conflicts. reset --keep moves main without
# touching uncommitted work, and refuses (leaving everything as is) when that
# work overlaps a file the move would change.
realign_local_main() {
  local n
  n="$(git cherry origin/main HEAD | grep -c "^+" || true)"
  [ "$n" -gt 0 ] || return 0
  if [ "$REALIGN" = true ]; then
    if git reset -q --keep origin/main 2>/dev/null; then
      echo "REALIGNED: local main moved to origin/main ($n local commit(s) were already there by content); uncommitted work kept"
    else
      echo "REALIGN-BLOCKED: uncommitted work overlaps a file the reset would change; local main left where it was"
      echo "Follow \"Realign refused\" in $REF: it names the blocking files and releases only those identical to origin"
    fi
  else
    echo "LOCAL-MAIN-DIVERGED: local main carries $n commit(s) whose content is on origin under different hashes."
    echo "Do not rebase them. Realign with: git reset --keep origin/main (team option: git config brain.debrief.realign true)"
  fi
}

# Push the rebased worktree head, then verify by content from the main tree.
finish_worktree_push() {
  # Capture the rebased head now: once the worktree is removed it is gone.
  PUSHED_HEAD="$(git -C "$WT" rev-parse HEAD)"
  if git -C "$WT" push --quiet origin HEAD:main; then
    if verify_pushed; then
      RES=0
      echo "PUSHED-VIA-WORKTREE: the work is on origin; the main tree was not touched"
      realign_local_main
    else
      RES=41
    fi
  else
    RES=40; echo "PUSH-RACE: origin advanced between fetch and push; the push was refused, the commit is safe locally"
  fi
}

# Team option. Only daily-log/ and memory/ files, only when every line of the
# local side already exists on the origin side: taking origin then loses
# nothing, and the choice is declared in the output. A file with unique
# lines on both sides is left for a human.
auto_resolve_in_worktree() {
  [ "$AUTO_TAKE" = true ] || return 0
  local tries=0 unmerged f local_side origin_side resolved wgd
  wgd="$(git -C "$WT" rev-parse --absolute-git-dir)"
  while [ "$tries" -lt 5 ]; do
    tries=$((tries+1))
    unmerged="$(git -C "$WT" diff --name-only --diff-filter=U)"
    [ -n "$unmerged" ] || break
    resolved=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in daily-log/*|memory/*) ;; *) continue ;; esac
      # During a rebase HEAD is the origin side and REBASE_HEAD the local
      # commit being replayed. A side that is missing (deleted on one side)
      # is never resolved automatically.
      local_side="$(git -C "$WT" show "REBASE_HEAD:$f" 2>/dev/null)" || continue
      origin_side="$(git -C "$WT" show "HEAD:$f" 2>/dev/null)" || continue
      if [ -z "$(comm -23 <(printf "%s\n" "$local_side" | LC_ALL=C sort -u) <(printf "%s\n" "$origin_side" | LC_ALL=C sort -u))" ]; then
        git -C "$WT" checkout --ours -- "$f" && git -C "$WT" add -- "$f"
        resolved=1
        echo "AUTO-TAKE: $f -> origin side kept; the local side was a strict subset of it (no line lost)"
      fi
    done <<UNMERGED_LIST
$unmerged
UNMERGED_LIST
    [ "$resolved" = 1 ] || break
    [ -z "$(git -C "$WT" diff --name-only --diff-filter=U)" ] || break
    if ! GIT_EDITOR=true git -C "$WT" rebase --continue >/dev/null 2>&1; then
      # A commit whose whole content was taken from origin is now empty.
      # Recent git drops it on --continue; older versions stop and ask for a
      # skip, which is the only skip the engine performs on its own, and it
      # says so. A --continue that fails for any other reason is never
      # answered with a skip.
      if { [ -d "$wgd/rebase-merge" ] || [ -d "$wgd/rebase-apply" ]; } \
         && [ -z "$(git -C "$WT" diff --name-only --diff-filter=U)" ] \
         && git -C "$WT" diff --cached --quiet 2>/dev/null; then
        GIT_EDITOR=true git -C "$WT" rebase --skip >/dev/null 2>&1 || true
        echo "SKIP-EMPTY: the session commit became empty after AUTO-TAKE (its content is already on origin)"
      fi
    fi
  done
}

BEHIND="$(git rev-list --count HEAD..origin/main)"
if [ "$BEHIND" -gt 0 ]; then
  # quotePath=false and cut -c4- keep paths with spaces or non-ASCII intact.
  DIRTY="$(git -c core.quotePath=false status --porcelain | grep -v "^??" | cut -c4-)"
  if [ -n "$DIRTY" ]; then
    # Physical path: mktemp may return a symlinked directory while git records
    # the resolved one, and `git worktree remove` needs the two to match.
    WTB="$(cd "$(mktemp -d)" && pwd -P)"; WT="$WTB/wt"
    if ! git worktree add --detach --quiet "$WT" HEAD; then
      rm -rf "$WTB"
      echo "DEFER: could not create a temporary worktree; push postponed, commit kept locally"; exit 10
    fi
    RES=10
    if git -C "$WT" rebase --quiet origin/main >/dev/null 2>&1; then
      finish_worktree_push
    else
      auto_resolve_in_worktree
      WGD="$(git -C "$WT" rev-parse --absolute-git-dir)"
      if [ -d "$WGD/rebase-merge" ] || [ -d "$WGD/rebase-apply" ]; then
        RES=21
        echo "CONFLICT-WORKTREE: the rebase is stopped inside the temporary worktree, not aborted; the main tree was not touched"
        echo "worktree: $WT"
        echo "conflicted files:"
        git -C "$WT" diff --name-only --diff-filter=U
      else
        finish_worktree_push
      fi
    fi
    # On exit 21 the worktree stays: the rebase to finish lives there.
    if [ "$RES" != 21 ]; then
      git worktree remove --force "$WT" >/dev/null 2>&1 || true
      git worktree prune >/dev/null 2>&1 || true
      rm -rf "$WTB"
    fi
    exit $RES
  fi
  if ! git pull --rebase --quiet origin main; then
    echo "CONFLICT: the rebase stopped on a conflict in the main tree; resolve it inside the rebase"; exit 20
  fi
fi
PUSHED_HEAD="$(git rev-parse HEAD)"
git push --quiet origin main || { echo "PUSH-RACE: origin advanced between fetch and push; the push was refused, the commit is safe locally"; exit 40; }
verify_pushed || exit 41
echo "PUSHED"
