#!/usr/bin/env bash
# Coherence check for docs/GOVERNANCE.md step 3, read-only.
#
#   scripts/governance-check.sh
#
# Prints one "FINDING: ..." line per problem. Exit 0 when clean or when the
# sensitive list has no active pattern (then there is nothing to be coherent
# with), 1 when at least one finding was printed. Run by /system-checkup.
#
# What it cross-checks: the sensitive list against the registry (someone must
# own the scopes, and owners need a github login for the CI tripwire), the
# hook activation on this clone, the workflow file, and, when CODEOWNERS
# exists, the two lists against each other in both directions.
set -u
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
. "$REPO_ROOT/scripts/lib/path-list.sh"
. "$REPO_ROOT/scripts/lib/operator-registry.sh"
export OPERATORS_DIR="${OPERATORS_DIR:-$REPO_ROOT/operators}"
SENSITIVE="$REPO_ROOT/.github/sensitive-paths.txt"
CODEOWNERS="$REPO_ROOT/.github/CODEOWNERS"
WORKFLOW="$REPO_ROOT/.github/workflows/sensitive-tripwire.yml"

if ! list_has_active_patterns "$SENSITIVE"; then
  echo "governance-check: sensitive paths inactive (no pattern in .github/sensitive-paths.txt); nothing to check"
  exit 0
fi

_login() { printf '%s' "$1" | sed 's/^@//' | tr '[:upper:]' '[:lower:]'; }

# Normalise a CODEOWNERS path column: no leading or trailing slash.
_co_path() { local p="$1"; p="${p#/}"; printf '%s' "${p%/}"; }

run_checks() {
  local owners s login prefix pat line path all_owner owner_logins=""

  owners="$(sensitive_owner_slugs)"
  [ -n "$owners" ] || echo "FINDING: no operators/<slug>.md declares sensitive_owner: true; with active sensitive patterns every direct push of them is refused by the hook and flagged by the tripwire"
  for s in $owners; do
    login="$(operator_field "$s" github)"
    [ -n "$login" ] || echo "FINDING: operators/$s.md is a sensitive owner without a github value: the CI tripwire cannot recognise their pushes"
    owner_logins="$owner_logins $(_login "$login")"
  done

  [ "$(git -C "$REPO_ROOT" config core.hooksPath 2>/dev/null || true)" = "githooks" ] \
    || echo "FINDING: pre-push hook not active on this clone: run git config core.hooksPath githooks"
  [ -f "$WORKFLOW" ] || echo "FINDING: CI tripwire workflow missing: .github/workflows/sensitive-tripwire.yml"

  [ -f "$CODEOWNERS" ] || return 0

  # Every active sensitive pattern needs a CODEOWNERS line for its fixed
  # prefix (the part before the first `*`), or PR reviews on it go unrouted.
  grep -vE '^[[:space:]]*(#|!|$)' "$SENSITIVE" | while IFS= read -r pat; do
    pat="${pat%$'\r'}"
    prefix="${pat%%\**}"; prefix="${prefix%/}"
    [ -n "$prefix" ] || continue
    if ! awk -v want="$prefix" '
        /^[[:space:]]*(#|$)/ { next }
        { p = $1; sub(/^\//, "", p); sub(/\/$/, "", p); if (p == want) found = 1 }
        END { exit !found }' "$CODEOWNERS"; then
      echo "FINDING: sensitive pattern '$pat' has no CODEOWNERS line for '$prefix': PR reviews on it are not routed"
    fi
  done

  # Every CODEOWNERS line routed only to sensitive owners should itself be a
  # sensitive pattern, or the hook and the tripwire ignore a scope the map
  # treats as owner-only.
  grep -vE '^[[:space:]]*(#|$)' "$CODEOWNERS" | while IFS= read -r line; do
    path="$(_co_path "$(printf '%s' "$line" | awk '{print $1}')")"
    case "$path" in ''|*\**) continue ;; esac
    all_owner=yes
    for login in $(printf '%s' "$line" | awk '{for (i = 2; i <= NF; i++) print $i}'); do
      case " $owner_logins " in *" $(_login "$login") "*) ;; *) all_owner=no ;; esac
    done
    [ "$all_owner" = yes ] || continue
    if ! path_in_list "$SENSITIVE" "$path" && ! path_in_list "$SENSITIVE" "$path/probe.md"; then
      echo "FINDING: CODEOWNERS routes '$path' only to sensitive owners but .github/sensitive-paths.txt does not list it"
    fi
  done
}

out="$(run_checks)"
[ -n "$out" ] && printf '%s\n' "$out"
if printf '%s\n' "$out" | grep -q '^FINDING:'; then
  exit 1
fi
echo "governance-check: clean"
exit 0
