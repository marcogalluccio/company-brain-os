#!/usr/bin/env bash
# Registry reader for operators/. The one implementation of "who is running
# this, and what may they do" that scripts, hooks and CI share.
#
# Source it for the functions, or execute it as a small CLI:
#   scripts/lib/operator-registry.sh resolve [<git-name>]
#   scripts/lib/operator-registry.sh field <slug> <field>
#   scripts/lib/operator-registry.sh git-names <slug>
#   scripts/lib/operator-registry.sh is-sensitive-owner <slug>
#   scripts/lib/operator-registry.sh sensitive-owners
#   scripts/lib/operator-registry.sh slug-for-github <login>
#
# The registry is the folder named by OPERATORS_DIR (default: <repo>/operators),
# minus the three files that are not operators (CLAUDE.md, ONBOARDING.md,
# operator_template.md). Subfolders are outside the registry, which is what
# lets an archived operator keep its file without claiming an identity.
#
# Resolution rule, quoted from operators/CLAUDE.md: resolve the active
# operator by matching `git config user.name` against every registry file's
# `git_names`. Exactly one match: proceed. Zero or multiple matches: stop and
# tell the user how to fix their identity or the registry. Never guess, never
# derive a slug from the name itself.

registry_dir() {
  printf '%s\n' "${OPERATORS_DIR:-$(git rev-parse --show-toplevel)/operators}"
}

registry_files() {
  local dir f
  dir="$(registry_dir)"
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in CLAUDE.md|ONBOARDING.md|operator_template.md) continue ;; esac
    printf '%s\n' "$f"
  done
}

operator_file() { printf '%s\n' "$(registry_dir)/$1.md"; }

# The YAML block between the first two `---` lines, nothing else.
_or_frontmatter() { awk '/^---$/{if(f)exit;f=1;next} f' "$1"; }

# operator_field <slug> <field>: the scalar value of a top-level key, trimmed.
operator_field() {
  local file
  file="$(operator_file "$1")"
  [ -f "$file" ] || return 1
  _or_frontmatter "$file" | awk -v k="$2" '
    index($0, k ":") == 1 {
      v = substr($0, length(k) + 2)
      sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
      print v; exit
    }'
}

# operator_git_names <slug>: the items of the git_names list, one per line.
# Bounded to that list: another list key ends it, and the body is never read.
operator_git_names() {
  local file
  file="$(operator_file "$1")"
  [ -f "$file" ] || return 1
  _or_frontmatter "$file" | awk '
    /^git_names:/ { g = 1; next }
    /^[A-Za-z_]+:/ { g = 0 }
    g && /^[[:space:]]*-[[:space:]]/ {
      v = $0; sub(/^[[:space:]]*-[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
      print v
    }'
}

# resolve_operator <git-name>: prints the slug of the single registry file
# whose git_names claims <git-name>; otherwise IDENTITY ERROR on stderr, exit 1.
resolve_operator() {
  local name="$1" f slug matches="" n=0
  if [ -z "$name" ]; then
    echo "IDENTITY ERROR: git config user.name is empty. Set it as described in operators/ONBOARDING.md Step 4." >&2
    return 1
  fi
  while IFS= read -r f; do
    slug="$(basename "$f" .md)"
    if operator_git_names "$slug" | grep -qxF -- "$name"; then
      matches="$matches $slug"
      n=$((n + 1))
    fi
  done < <(registry_files)
  if [ "$n" != 1 ]; then
    echo "IDENTITY ERROR: git user.name \"$name\" matches $n operator files:$matches" >&2
    echo "Exactly one operators/<slug>.md must claim this value in git_names." >&2
    echo "Fix your identity or the registry (see operators/CLAUDE.md), then rerun." >&2
    return 1
  fi
  printf '%s\n' "${matches# }"
}

# is_sensitive_owner <slug>: true only for an explicit `sensitive_owner: true`.
is_sensitive_owner() { [ "$(operator_field "$1" sensitive_owner 2>/dev/null)" = "true" ]; }

sensitive_owner_slugs() {
  local f slug
  while IFS= read -r f; do
    slug="$(basename "$f" .md)"
    is_sensitive_owner "$slug" && printf '%s\n' "$slug"
  done < <(registry_files)
  return 0
}

# slug_for_github <login>: GitHub logins are case-insensitive and sometimes
# written with a leading @, so both sides are normalised before comparing.
_or_login() { printf '%s' "$1" | sed 's/^@//' | tr '[:upper:]' '[:lower:]'; }

slug_for_github() {
  local want f slug
  want="$(_or_login "$1")"
  [ -n "$want" ] || return 1
  while IFS= read -r f; do
    slug="$(basename "$f" .md)"
    if [ "$(_or_login "$(operator_field "$slug" github)")" = "$want" ]; then
      printf '%s\n' "$slug"
      return 0
    fi
  done < <(registry_files)
  return 1
}

# CLI mode: only when executed, never when sourced.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -u
  cmd="${1:-}"
  [ $# -gt 0 ] && shift
  case "$cmd" in
    resolve)            resolve_operator "${1:-$(git config user.name)}" ;;
    field)              operator_field "${1:-}" "${2:-}" ;;
    git-names)          operator_git_names "${1:-}" ;;
    is-sensitive-owner) is_sensitive_owner "${1:-}" ;;
    sensitive-owners)   sensitive_owner_slugs ;;
    slug-for-github)    slug_for_github "${1:-}" ;;
    *)
      echo "usage: scripts/lib/operator-registry.sh resolve [<git-name>] | field <slug> <field> | git-names <slug> | is-sensitive-owner <slug> | sensitive-owners | slug-for-github <login>" >&2
      exit 64 ;;
  esac
fi
