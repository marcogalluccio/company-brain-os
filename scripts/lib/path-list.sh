#!/usr/bin/env bash
# Pattern-list matcher shared by the pre-push hook, the CI tripwire, the
# debrief classifier and their tests. Source it, do not execute it.
#
# A pattern list is a plain text file, one entry per line:
#   - blank lines and lines starting with `#` are ignored;
#   - a line starting with `!` is an exception: a path matching it is never
#     listed, whatever the other lines say, wherever the line sits;
#   - every other line is a shell glob matched against the whole repo-relative
#     path, and `*` also matches `/`, so `skills/*` covers every depth.
# Exceptions are evaluated in a first pass, before any pattern, so a carve-out
# wins even against a broader pattern written above or below it.

# Strip a trailing carriage return: lists edited on Windows carry one.
_pl_line() { printf '%s' "${1%$'\r'}"; }

# path_is_exception <list-file> <path>
# Exit 0 if <path> matches an exception line, 1 otherwise or if unreadable.
path_is_exception() {
  local list="$1" p="$2" pat
  [ -r "$list" ] || return 1
  while IFS= read -r pat || [ -n "$pat" ]; do
    pat="$(_pl_line "$pat")"
    case "$pat" in \!*) ;; *) continue ;; esac
    # shellcheck disable=SC2254  # unquoted on purpose: the line is a glob
    case "$p" in ${pat#\!}) return 0 ;; esac
  done < "$list"
  return 1
}

# path_in_list <list-file> <path>
# Exit 0 if <path> matches an active pattern and no exception; 1 if it does
# not; 2 if the list file cannot be read (callers treat 2 as "not listed").
path_in_list() {
  local list="$1" p="$2" pat
  [ -r "$list" ] || return 2
  path_is_exception "$list" "$p" && return 1
  while IFS= read -r pat || [ -n "$pat" ]; do
    pat="$(_pl_line "$pat")"
    case "$pat" in ''|\#*|\!*) continue ;; esac
    # shellcheck disable=SC2254
    case "$p" in $pat) return 0 ;; esac
  done < "$list"
  return 1
}

# list_has_active_patterns <list-file>
# Exit 0 if at least one line is neither blank, comment, nor exception.
# A list with no active pattern makes every consumer inert on purpose.
list_has_active_patterns() {
  local list="$1"
  [ -r "$list" ] || return 1
  grep -qvE '^[[:space:]]*(#|!|$)' "$list"
}
