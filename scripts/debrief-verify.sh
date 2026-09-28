#!/usr/bin/env bash
# Content check after a push: did the local commits' changes actually land on
# origin/main, in both directions?
#
# A push can exit 0 while a commit was dropped on the way (a rebase --skip, a
# replay resolved entirely to the other side), and comparing commit hashes
# cannot tell: after a rebase the pushed head is legitimately a different
# object, and origin may legitimately hold more than we pushed (someone else's
# commit on the same file). So the check is by content, on the files given
# (default: every file the range touches): every non-empty line ADDED between
# <from> and <to> must exist verbatim in origin/main's copy of the file, and
# every non-empty line REMOVED must be gone from it there too (a commit that
# only deletes lines, or a whole file, adds nothing anywhere, so checking
# additions alone would let a dropped deletion through silently).
#
# Added and removed lines are read from the diff's hunk bodies only (after the
# first "@@"), never from its "--- a/file" / "+++ b/file" headers by matching
# their prefix: a removed or added line whose own content starts with "---" or
# "+++" (a frontmatter fence, a markdown rule) would otherwise be mistaken for
# a header and silently dropped from the check.
#
# A removed line is only evidence of a dropped deletion when it is
# unambiguous: it occurs exactly once in the file before the range and zero
# times after. A duplicate line (a repeated bullet, a fence, a table rule)
# fails that test and is skipped rather than guessed at, because a surviving
# twin proves nothing about the one that was removed; the same test skips a
# line that was moved within the file rather than dropped, since a move
# leaves it in the post-image. This deliberately under-checks a deletion made
# only of duplicated lines; the whole-file-deletion branch and the line's own
# unique occurrences still catch the primary hazard, and under-checking here
# is silent-safe in a way a false alarm is not.
#
# Under-checking a line is one thing; under-checking an entire range is
# another. If a range touched files but every one of its changes turned out
# to be unconfirmable, nothing in the range was actually confirmed against
# origin/main, and printing success would be exactly the false green light
# this script exists to prevent. That includes a range whose only changes
# were removed lines that failed the uniqueness test above, or blank lines,
# or a change that renders no hunk at all (a binary file, a mode-only
# change, a zero-byte file added or removed) and so has nothing line-based
# to examine in the first place. Any of these is reported as a failure
# ("nothing here could be confirmed"), not as success. A range that touches
# nothing at all (<from> and <to> identical, or no file in scope changed) is
# a different, legitimate case: there is nothing to verify, which is
# success by definition, not a gap in the check.
#
# Usage: scripts/debrief-verify.sh <from-sha> <to-sha> <pushed-sha|-> [file]...
#   <pushed-sha> is informational: when origin/main differs from it, origin
#   moved on after the push, which is not an error. "-" means unknown.
# Exit: 0 every change present as expected, or nothing to check; 1 something
# missing, not removed, or unconfirmable (listed on stdout); 64 usage, which
# includes a <from> or <to> that does not name a commit.
set -e
if [ "$#" -lt 3 ]; then
  echo "USAGE: scripts/debrief-verify.sh <from-sha> <to-sha> <pushed-sha|-> [file]..."
  exit 64
fi
FROM="$1"; TO="$2"; PUSHED="$3"; shift 3

# Both ends of the range must name a commit before anything else runs. An
# unresolvable end is not an empty range: git refuses to diff it, the file
# list comes back empty, and every count this script reasons from stays at
# zero, which reads as "there was nothing to verify" and prints VERIFY OK on
# a range that was never examined. Callers act on that verdict by discarding
# work, so it has to be a usage error rather than a success.
for REV in "$FROM" "$TO"; do
  git rev-parse --verify --quiet "$REV^{commit}" >/dev/null || {
    echo "USAGE: \"$REV\" does not name a commit; nothing was checked."
    exit 64
  }
done

git fetch origin main --quiet
ORIGIN_MAIN="$(git rev-parse origin/main)"
if [ "$PUSHED" != "-" ] && [ "$ORIGIN_MAIN" != "$PUSHED" ]; then
  echo "NOTE: origin/main ($ORIGIN_MAIN) moved past the pushed commit ($PUSHED); the content check decides."
fi

ORIGIN_COPY="$(mktemp)"
PRE_COPY="$(mktemp)"
POST_COPY="$(mktemp)"
FILE_LIST="$(mktemp)"
trap 'rm -f "$ORIGIN_COPY" "$PRE_COPY" "$POST_COPY" "$FILE_LIST"' EXIT
MISS=0
TOUCHED=0
CHECKED=0
# The list of files the range touched, materialised before the loop reads it.
# Feeding the loop from a process substitution instead would put this command
# in a subshell whose exit status nothing observes: if it failed, the loop
# would simply see no files and the run would end in VERIFY OK on a range
# nothing was read from. Written to a file it is an ordinary command, so a
# failure ends the script under set -e instead of turning into a verdict.
# -z: file names may contain spaces.
git diff --name-only -z "$FROM" "$TO" -- "$@" > "$FILE_LIST"
while IFS= read -r -d "" f; do
  # This file is touched by definition: it came out of the name-only diff
  # above, which lists every file the range changed, whether or not that
  # change renders as a hunk. Setting TOUCHED from loop membership, not from
  # anything about the diff's content, is what makes a binary file, a
  # mode-only change, or the add or delete of a zero-byte file count as
  # touched too: none of those render a "@@" hunk, so a count derived from
  # hunk bodies would miss them and let the range through as unconfirmed but
  # unflagged.
  TOUCHED=$((TOUCHED + 1))
  # Lines added and removed on this file, read from the hunk bodies only (the
  # part of the diff after the first "@@"), never by matching a line prefix
  # against the "--- a/file" / "+++ b/file" headers: a content line that
  # itself starts with "---" or "+++" would otherwise be mistaken for one.
  DIFF="$(git diff "$FROM" "$TO" -- "$f")"
  # Whether this file's diff has anything line-based to examine at all. A
  # binary file, a mode-only change, or a zero-byte file being added or
  # removed renders no hunk, so this is 0 even though the file is touched
  # (TOUCHED was already set above, independently of this count).
  BODY_N="$(printf '%s\n' "$DIFF" | awk '/^@@/{h=1;next} h && /^[+-]/{c++} END{print c+0}')"
  [ "$BODY_N" -gt 0 ] || continue
  # Blank lines prove nothing about content and are skipped from here on.
  ADDED="$(printf '%s\n' "$DIFF" | awk '/^@@/{h=1;next} h && /^\+/{print substr($0,2)}' | grep -v "^$" || true)"
  REMOVED="$(printf '%s\n' "$DIFF" | awk '/^@@/{h=1;next} h && /^-/{print substr($0,2)}' | grep -v "^$" || true)"

  if ! git cat-file -e "$TO:$f" 2>/dev/null; then
    # The range deleted this file outright. The deletion landed only if
    # origin/main does not have the file either. Either way this is a real
    # check: it counts toward CHECKED regardless of its outcome.
    CHECKED=$((CHECKED + 1))
    if git cat-file -e "$ORIGIN_MAIN:$f" 2>/dev/null; then
      echo "PUSH-INCOMPLETE: $f still exists on origin/main (the local commits deleted it)"
      MISS=1
    fi
    continue
  fi

  if ! git cat-file -e "$ORIGIN_MAIN:$f" 2>/dev/null; then
    CHECKED=$((CHECKED + 1))
    echo "PUSH-INCOMPLETE: $f is missing on origin/main (the local commits changed it)"
    MISS=1; continue
  fi
  git show "$ORIGIN_MAIN:$f" > "$ORIGIN_COPY"

  if [ -n "$ADDED" ]; then
    while IFS= read -r line; do
      CHECKED=$((CHECKED + 1))
      if ! grep -qxF -- "$line" "$ORIGIN_COPY"; then
        echo "PUSH-INCOMPLETE: line missing on origin/main in $f:"
        echo "  +$line"
        MISS=1
      fi
    done <<ADDED_LINES
$ADDED
ADDED_LINES
  fi

  if [ -n "$REMOVED" ]; then
    # Pre- and post-image of this file, to tell an unambiguous removed line
    # (proof the deletion did or did not land) from a duplicate or a move.
    if git cat-file -e "$FROM:$f" 2>/dev/null; then
      git show "$FROM:$f" > "$PRE_COPY"
    else
      : > "$PRE_COPY"
    fi
    git show "$TO:$f" > "$POST_COPY"
    while IFS= read -r line; do
      PRE_N="$(grep -cxF -- "$line" "$PRE_COPY" || true)"
      POST_N="$(grep -cxF -- "$line" "$POST_COPY" || true)"
      if [ "$PRE_N" = 1 ] && [ "$POST_N" = 0 ]; then
        CHECKED=$((CHECKED + 1))
        if grep -qxF -- "$line" "$ORIGIN_COPY"; then
          echo "PUSH-INCOMPLETE: line not removed on origin/main in $f:"
          echo "  -$line"
          MISS=1
        fi
      fi
    done <<REMOVED_LINES
$REMOVED
REMOVED_LINES
  fi
done < "$FILE_LIST"

if [ "$MISS" = 0 ]; then
  if [ "$TOUCHED" -gt 0 ] && [ "$CHECKED" = 0 ]; then
    # The range changed something (TOUCHED>0), but nothing about those
    # changes was actually confirmed against origin/main: every removed line
    # failed the uniqueness test, or every change was blank, or nothing in
    # the range rendered a hunk to begin with (a binary file, a mode-only
    # change, a zero-byte file added or removed). A genuinely empty range
    # never reaches here: TOUCHED stays 0 for it, and that case exits 0
    # below as intended.
    echo "PUSH-INCOMPLETE: nothing in this range could be confirmed by content (every change was binary, mode-only, a blank line, or a removed line that repeats elsewhere in its file); the push could not be verified."
    exit 1
  fi
  echo "VERIFY OK: every local change (added or removed) is reflected on origin/main."
  exit 0
fi
echo "PUSH-INCOMPLETE: origin/main does not hold all the committed work (details above)."
exit 1
