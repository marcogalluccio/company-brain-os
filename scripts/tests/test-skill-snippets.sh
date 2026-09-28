#!/usr/bin/env bash
# Static checks on the skill texts: the git engine stays in one place, the
# snippets survive the mechanism that hands them to the shell, and the exit-code
# table cannot drift from the script.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
fail=0
FILES="$(ls skills/*/SKILL.md skills/*/reference/*.md 2>/dev/null)"

# 1. No positional parameter in any skill file: the relay that runs a skill
#    substitutes $1, $2, ... with the invocation arguments before the shell
#    sees the snippet, silently changing what it does.
if grep -nE '\$\{?[1-9]' $FILES; then
  echo "FAIL: positional parameter in a skill file (see above)"; fail=1
fi

# 2. The engine lives in scripts/debrief-push.sh only: no fenced block in a
#    skill file fetches, rebases and pushes on its own.
for f in $FILES; do
  awk -v file="$f" '
    /^[[:space:]]*```/ {
      if (inb) {
        if (buf ~ /git fetch origin/ && buf ~ /rebase/ && buf ~ /git push/) {
          print "FAIL: inline engine in " file " (fenced block opened at line " start ")"; bad=1
        }
        inb=0
      } else { inb=1; buf=""; start=NR }
      next
    }
    inb { buf = buf $0 "\n" }
    END { exit bad }' "$f" || fail=1
done

# 3. --skip is never the fallback of a failed --continue, in prose or code.
if grep -rnE 'rebase --continue.*\|\|.*rebase --skip' skills scripts; then
  echo "FAIL: --skip used as the fallback of --continue (see above)"; fail=1
fi

# 4. The engine and the reference agree on the exit codes. 30 is raised by
#    the guards in the reference's own snippets, 75 by the lock wrapper.
REF="skills/session-debrief/reference/push-outcomes.md"
if [ ! -f "$REF" ]; then
  echo "FAIL: $REF missing"; fail=1
else
  SCRIPT_CODES="$( { grep -oE '(exit|RES=)[ ]?[0-9]+' scripts/debrief-push.sh | grep -oE '[0-9]+'; echo 30; echo 75; } | sort -nu | tr '\n' ' ')"
  REF_CODES="$(grep -oE '^## exit [0-9]+' "$REF" | cut -d' ' -f3 | sort -nu | tr '\n' ' ')"
  if [ "$SCRIPT_CODES" != "$REF_CODES" ]; then
    echo "FAIL: exit codes differ between the engine and the reference"
    echo "  engine + 30 + 75: $SCRIPT_CODES"; echo "  reference:        $REF_CODES"; fail=1
  fi
fi

# 5. The path the engine prints on a non-zero exit exists.
PRINTED="$(grep -oE '^REF="[^"]+"' scripts/debrief-push.sh | cut -d'"' -f2)"
[ -n "$PRINTED" ] && [ -f "$PRINTED" ] || { echo "FAIL: the engine prints \"$PRINTED\", which does not exist"; fail=1; }

# 6. Every shell or Python script in scripts/ has a test under scripts/tests
#    that names it, in a file other than this one: this file's own checks
#    above name every shell script by necessity, which would satisfy the
#    check for free. Python scripts get no such free pass from this file, so
#    an uncovered one is only ever caught here.
SELF="scripts/tests/$(basename "$0")"
for s in scripts/*.sh scripts/git-locked scripts/*.py; do
  [ -f "$s" ] || continue
  name="$(basename "$s")"
  grep -rlF -- "$name" scripts/tests 2>/dev/null | grep -vxF "$SELF" | grep -q . || { echo "FAIL: no test under scripts/tests names $name"; fail=1; }
done

# 7. Every Python snippet embedded in a SKILL.md compiles under the running
#    interpreter. Bash single-quoting a `python3 -c '...'` argument only
#    guarantees the shell hands python3 a string unmodified; it says nothing
#    about whether that string is valid Python. In particular, nesting the
#    same quote character inside an f-string's braces (even backslash-escaped)
#    is a SyntaxError before Python 3.12, and grepping for stray text can't
#    catch it because the snippet is syntactically fine shell, just broken
#    Python. Extract every such snippet and py_compile it so a broken one
#    fails here, at review time, instead of at the next live run.
PYCOUNT=0
PYTMP="$(mktemp -d)"
trap 'rm -rf "$PYTMP"' EXIT
for f in $FILES; do
  in_snip=0
  n=0
  snipfile=""
  start=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if [ "$in_snip" = 1 ]; then
      if [ "$line" = "'" ]; then
        in_snip=0
        if ! python3 -m py_compile "$snipfile" 2>"$PYTMP/err.txt"; then
          echo "FAIL: Python snippet in $f (opened at line $start) does not compile:"
          sed 's/^/  /' "$PYTMP/err.txt"
          fail=1
        fi
      else
        printf '%s\n' "$line" >>"$snipfile"
      fi
      continue
    fi
    case "$line" in
      *"python3 -c '"*)
        after=${line#*"python3 -c '"}
        case "$after" in
          *"'"*)
            # Single-line: `python3 -c '...'` opens and closes on one line.
            content=${after%"'"*}
            PYCOUNT=$((PYCOUNT + 1))
            snipfile="$PYTMP/snip_$PYCOUNT.py"
            printf '%s\n' "$content" >"$snipfile"
            if ! python3 -m py_compile "$snipfile" 2>"$PYTMP/err.txt"; then
              echo "FAIL: Python snippet in $f:$n does not compile:"
              sed 's/^/  /' "$PYTMP/err.txt"
              fail=1
            fi
            ;;
          *)
            trimmed=$(printf '%s' "$after" | tr -d '[:space:]')
            if [ -n "$trimmed" ]; then
              echo "FAIL: unrecognized python3 -c shape in $f:$n (trailing text after the opening quote, no closing quote on the same line): $line"
              fail=1
            else
              # Multi-line: opening quote is the last thing on the line; the
              # snippet runs until a line that is exactly a closing quote.
              in_snip=1
              start=$n
              PYCOUNT=$((PYCOUNT + 1))
              snipfile="$PYTMP/snip_$PYCOUNT.py"
              : >"$snipfile"
            fi
            ;;
        esac
        ;;
    esac
  done <"$f"
  if [ "$in_snip" = 1 ]; then
    echo "FAIL: $f opens a python3 -c snippet at line $start with no closing quote"
    fail=1
  fi
done
if [ "$PYCOUNT" = 0 ]; then
  echo "FAIL: no embedded Python snippet found to compile-check (the extractor matched nothing)"
  fail=1
fi

[ "$fail" = 0 ] && echo "OK: skill snippets" || exit 1
