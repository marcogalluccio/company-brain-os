#!/usr/bin/env bash
# Classify repo paths before a debrief commits them on main.
#
#   scripts/classify-paths.sh [--operator <slug>] <path>...
#
# One line per path on stdout, "<class>\t<path>":
#   structural   listed in .github/structural-paths.txt: feature branch, every operator
#   sensitive    listed in .github/sensitive-paths.txt and the operator is not
#                a sensitive owner (or no operator was given): proposal PR
#   carve-out    an exception in either list: lands on main with the debrief
#   normal       everything else
# Precedence: structural, then sensitive, then carve-out, then normal.
# With --operator, one "operator=<slug> sensitive_owner=yes|no" line on stderr.
#
# Exit 0 when every path is normal or carve-out, 4 when at least one path is
# structural or sensitive, 64 on usage error. A list that is missing or has no
# active pattern simply lists nothing, so an unadopted template classifies
# everything as normal.
set -u
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
. "$REPO_ROOT/scripts/lib/path-list.sh"
. "$REPO_ROOT/scripts/lib/operator-registry.sh"
STRUCTURAL="${STRUCTURAL_PATHS_FILE:-$REPO_ROOT/.github/structural-paths.txt}"
SENSITIVE="${SENSITIVE_PATHS_FILE:-$REPO_ROOT/.github/sensitive-paths.txt}"

usage() { echo "usage: scripts/classify-paths.sh [--operator <slug>] <path>..." >&2; }

operator=""
if [ "${1:-}" = "--operator" ]; then
  operator="${2:-}"
  [ -n "$operator" ] || { usage; exit 64; }
  shift 2
fi
[ $# -gt 0 ] || { usage; exit 64; }

owner=no
if [ -n "$operator" ]; then
  if [ ! -f "$(operator_file "$operator")" ]; then
    echo "warning: operators/$operator.md not found; classifying as a non-owner" >&2
  elif is_sensitive_owner "$operator"; then
    owner=yes
  fi
  echo "operator=$operator sensitive_owner=$owner" >&2
fi

listed=0
for p in "$@"; do
  p="${p#./}"
  if path_in_list "$STRUCTURAL" "$p"; then
    cls=structural
  elif [ "$owner" = no ] && path_in_list "$SENSITIVE" "$p"; then
    cls=sensitive
  elif path_is_exception "$STRUCTURAL" "$p" || path_is_exception "$SENSITIVE" "$p"; then
    cls=carve-out
  else
    cls=normal
  fi
  case "$cls" in structural|sensitive) listed=1 ;; esac
  printf '%s\t%s\n' "$cls" "$p"
done

[ "$listed" = 0 ] && exit 0
exit 4
