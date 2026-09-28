#!/usr/bin/env bash
# CI-side detection for the sensitive-path tripwire (docs/GOVERNANCE.md step 3).
#
#   scripts/sensitive-tripwire-detect.sh --before <sha|zero> --after <sha> --actor <github-login>
#
# Prints a small report on stdout and exits 0 on any completed scan; deciding
# what to do with a hit is the workflow's job, not this script's:
#   hit=yes|no
#   anomaly=<text, or empty>
#   files:
#   <one hit per line>
#
# A hit is: the actor is not a sensitive owner (per operators/) and at least
# one changed file matches .github/sensitive-paths.txt; or commits in the
# range are authored under a sensitive owner's git identity while the actor
# is not one, which usually means a misconfigured user.name on some machine;
# or the range itself could not be diffed, so no scan happened at all.
# The actor is a GitHub login and is matched against the `github` field of
# the registry, never against a name written here.
set -u
usage() { echo "usage: scripts/sensitive-tripwire-detect.sh --before <sha|zero> --after <sha> --actor <github-login>" >&2; }

BEFORE=""; AFTER=""; ACTOR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --before) BEFORE="${2:-}"; shift 2 ;;
    --after)  AFTER="${2:-}";  shift 2 ;;
    --actor)  ACTOR="${2:-}";  shift 2 ;;
    *) usage; exit 64 ;;
  esac
done
[ -n "$AFTER" ] && [ -n "$ACTOR" ] || { usage; exit 64; }

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
. "$REPO_ROOT/scripts/lib/path-list.sh"
. "$REPO_ROOT/scripts/lib/operator-registry.sh"
export OPERATORS_DIR="${OPERATORS_DIR:-$REPO_ROOT/operators}"
SENSITIVE="${SENSITIVE_PATHS_FILE:-$REPO_ROOT/.github/sensitive-paths.txt}"

report() {
  echo "hit=$1"
  echo "anomaly=$2"
  echo "files:"
  [ -n "$3" ] && printf '%s\n' "$3"
  return 0
}

if ! list_has_active_patterns "$SENSITIVE"; then
  report no "" ""
  exit 0
fi

ZERO=0000000000000000000000000000000000000000
if [ -z "$BEFORE" ] || [ "$BEFORE" = "$ZERO" ]; then
  # No previous tip (first push, or a new branch): scan the last commit
  # against its parent, or against the empty tree for a root commit.
  if git -C "$REPO_ROOT" rev-parse -q --verify "$AFTER^" >/dev/null 2>&1; then
    BASE="$AFTER^"; LOGRANGE="$AFTER^..$AFTER"
  else
    BASE="$(git hash-object -t tree /dev/null)"; LOGRANGE="$AFTER"
  fi
else
  BASE="$BEFORE"; LOGRANGE="$BEFORE..$AFTER"
fi

NL=$'\n'
hits=""
scan_failed=""
# An unreachable range (a rewritten history leaves one behind) makes git write
# nothing to stdout and exit non-zero, which is byte-identical to a clean scan
# unless the status is read. Capture it so a scan that did not happen is never
# reported as a scan that found nothing.
if changed="$(git -C "$REPO_ROOT" diff --name-only "$BASE" "$AFTER")"; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    path_in_list "$SENSITIVE" "$f" && hits="${hits:+$hits$NL}$f"
  done < <(printf '%s\n' "$changed")
else
  scan_failed="scan incomplete: git could not diff the range $BASE..$AFTER, so no file was checked"
fi

actor_is_owner=no
if slug="$(slug_for_github "$ACTOR")" && is_sensitive_owner "$slug"; then
  actor_is_owner=yes
fi

anomaly=""
if [ -n "$scan_failed" ]; then
  # The author scan reads the same unreachable range, so it is skipped too.
  anomaly="$scan_failed"
elif [ "$actor_is_owner" = no ]; then
  authors="$(git -C "$REPO_ROOT" log --format=%an "$LOGRANGE")"
  for s in $(sensitive_owner_slugs); do
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      if printf '%s\n' "$authors" | grep -qxF -- "$name"; then
        anomaly="commits authored under the git identity of sensitive owner '$s' were pushed by @$ACTOR, who is not one: check git config user.name on that machine"
      fi
    done < <(operator_git_names "$s")
  done
fi

if { [ "$actor_is_owner" = no ] && [ -n "$hits" ]; } || [ -n "$anomaly" ]; then
  report yes "$anomaly" "$hits"
else
  report no "$anomaly" "$hits"
fi
exit 0
