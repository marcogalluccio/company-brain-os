#!/usr/bin/env bash
# Bench for scripts/debrief-push.sh and scripts/debrief-verify.sh.
# Every scenario builds a throwaway bare origin plus two clones (operator one
# runs the engine, operator two plays the teammate who pushed meanwhile) and
# asserts the exit code, the markers printed, and the state of origin and of
# the main working tree afterwards.
#
# Usage: scripts/tests/debrief-push-bench.sh            (scripts from this repo)
#        scripts/tests/debrief-push-bench.sh <scripts-dir>
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="${1:-$ROOT/scripts}"
BASE="$(cd "$(mktemp -d)" && pwd -P)"
PASS=0; FAIL=0

say() { printf '\n=== %s ===\n' "$*"; }
ok()  { PASS=$((PASS+1)); echo "PASS: $*"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $*"; }

# mkrepo <name>: prints the path of the scenario directory. Layout:
#   <dir>/origin.git  bare remote
#   <dir>/A           operator one's clone, engine under test copied in
#   <dir>/B           operator two's clone
mkrepo() {
  local d="$BASE/$1"
  mkdir -p "$d"
  git init -q --bare -b main "$d/origin.git"
  git clone -q "$d/origin.git" "$d/A" 2>/dev/null
  git -C "$d/A" config user.name "Operator One"
  git -C "$d/A" config user.email "one@example.invalid"
  mkdir -p "$d/A/daily-log" "$d/A/memory/archive" "$d/A/operators" "$d/A/scripts" "$d/A/areas/notes"
  local s
  for s in debrief-push.sh debrief-verify.sh git-locked; do
    [ -f "$SCRIPTS/$s" ] && cp "$SCRIPTS/$s" "$d/A/scripts/$s" && chmod +x "$d/A/scripts/$s"
  done
  printf -- '---\nslug: op-one\ngit_names:\n  - Operator One\n---\n' > "$d/A/operators/op-one.md"
  printf -- '---\nslug: op-two\ngit_names:\n  - Operator Two\n---\n' > "$d/A/operators/op-two.md"
  printf 'registry rules\n' > "$d/A/operators/CLAUDE.md"
  printf 'line1\nline2\nline3\nline4\nline5\n' > "$d/A/daily-log/shared.md"
  printf 'index v0\n' > "$d/A/memory/MEMORY.md"
  printf 'project p\n' > "$d/A/memory/project_p.md"
  printf 'wip v0\n' > "$d/A/areas/notes/wip.md"
  printf 'base\n' > "$d/A/base.md"
  git -C "$d/A" add -A
  git -C "$d/A" commit -qm base
  git -C "$d/A" push -q origin main
  git clone -q "$d/origin.git" "$d/B" 2>/dev/null
  git -C "$d/B" config user.name "Operator Two"
  git -C "$d/B" config user.email "two@example.invalid"
  echo "$d"
}

# run_engine <clone> [args...]: runs the engine; leaves RC and OUT.
run_engine() {
  local dir="$1"; shift
  OUT="$(cd "$dir" && bash scripts/debrief-push.sh "$@" 2>&1)"; RC=$?
}
# other_pushes <scenario-dir> <file> <content>: operator two pushes a commit.
other_pushes() {
  ( cd "$1/B" && git pull -q --rebase origin main && mkdir -p "$(dirname "$2")" \
    && printf '%s' "$3" > "$2" && git add -- "$2" && git commit -qm "two: $2" && git push -q origin main )
}
origin_has() { git -C "$1/A" fetch -q origin main && git -C "$1/A" show "origin/main:$2" 2>/dev/null | grep -qF -- "$3"; }
ahead_count() { git -C "$1/A" fetch -q origin main && git -C "$1/A" rev-list --count origin/main..HEAD; }


# ---------------------------------------------------------------- S1
say "S1 clean push"
D=$(mkrepo s1)
printf 'today log\n' > "$D/A/daily-log/2026-01-15-op one.md"   # a space in the name: quoting must hold
run_engine "$D/A" "daily-log/2026-01-15-op one.md"
[ "$RC" = 0 ] || bad "S1 exit=$RC expected 0 -- $OUT"
echo "$OUT" | grep -q "^PUSHED$" || bad "S1 missing PUSHED marker"
echo "$OUT" | grep -q "^session commit: [0-9a-f]\{40\}$" || bad "S1 missing session commit line"
git -C "$D/A" fetch -q origin main
git -C "$D/A" log -1 --format=%s origin/main | grep -q "^debrief: [0-9-]* [0-9]* (op-one)$" || bad "S1 subject shape wrong: $(git -C "$D/A" log -1 --format=%s origin/main)"
origin_has "$D" "daily-log/2026-01-15-op one.md" "today log" && [ "$RC" = 0 ] && ok "S1 exit 0, content on origin, subject from the registry" || bad "S1 content not on origin"


# ---------------------------------------------------------------- S2
say "S2 dirty tree + origin ahead, no conflict -> worktree push, WIP intact"
D=$(mkrepo s2)
other_pushes "$D" other.md 'from two
'
# A commit an earlier run left behind rides the same push. The verified range
# starts at the fork point, so this commit is checked against origin too; a
# range starting at the session commit's parent would have let it out unchecked.
( cd "$D/A" && printf 'project p\ncarried over from an earlier run\n' > memory/project_p.md \
  && git add memory/project_p.md && git commit -qm "earlier run, never pushed" )
printf 'UNCOMMITTED PARALLEL WORK\n' > "$D/A/areas/notes/wip.md"
printf 'session one\n' > "$D/A/daily-log/2026-01-15-op-one.md"
run_engine "$D/A" daily-log/2026-01-15-op-one.md
[ "$RC" = 0 ] || bad "S2 exit=$RC expected 0 -- $OUT"
echo "$OUT" | grep -q "PUSHED-VIA-WORKTREE" || bad "S2 missing PUSHED-VIA-WORKTREE"
echo "$OUT" | grep -q "VERIFY OK" || bad "S2 missing VERIFY OK"
echo "$OUT" | grep -q "LOCAL-MAIN-DIVERGED" && bad "S2 reported divergence on a patch-identical replay"
grep -q "UNCOMMITTED PARALLEL WORK" "$D/A/areas/notes/wip.md" || bad "S2 WIP was touched"
[ -z "$(git -C "$D/A" worktree list --porcelain | grep -c '^worktree ' | grep -vx 1)" ] || bad "S2 temporary worktree left behind"
origin_has "$D" daily-log/2026-01-15-op-one.md "session one" && origin_has "$D" other.md "from two" \
  && origin_has "$D" memory/project_p.md "carried over from an earlier run" && [ "$RC" = 0 ] \
  && ok "S2 exit 0 via worktree, origin has both, the earlier commit rode the same push and was verified with it, WIP intact" \
  || bad "S2 origin content wrong"


# ---------------------------------------------------------------- S5
say "S5 usage guards: no argument, a directory, an unknown path -> exit 64, nothing committed"
D=$(mkrepo s5)
run_engine "$D/A"
[ "$RC" = 64 ] || bad "S5 no-arg exit=$RC expected 64"
printf 'x\n' > "$D/A/daily-log/x.md"
run_engine "$D/A" daily-log
[ "$RC" = 64 ] || bad "S5 directory exit=$RC expected 64 -- $OUT"
echo "$OUT" | grep -q "is a directory" || bad "S5 directory not named"
run_engine "$D/A" daily-log/does-not-exist.md
[ "$RC" = 64 ] || bad "S5 unknown path exit=$RC expected 64 -- $OUT"
[ "$(git -C "$D/A" rev-list --count HEAD)" = 1 ] && [ -z "$(git -C "$D/A" diff --cached --name-only)" ] \
  && ok "S5 exit 64 on every misuse, index and history untouched" || bad "S5 something was staged or committed"


# ---------------------------------------------------------------- S13
say "S13 identity and state guards: unknown operator (65), not on main (3), rebase in progress (2)"
D=$(mkrepo s13)
git -C "$D/A" config user.name "Nobody Registered"
printf 'session\n' > "$D/A/daily-log/2026-01-15-x.md"
run_engine "$D/A" daily-log/2026-01-15-x.md
[ "$RC" = 65 ] && echo "$OUT" | grep -q "IDENTITY ERROR" && [ "$(git -C "$D/A" rev-list --count HEAD)" = 1 ] \
  && ok "S13 unregistered name -> exit 65, nothing committed" || bad "S13 exit=$RC -- $OUT"
git -C "$D/A" config user.name "Operator One"
git -C "$D/A" checkout -q -b feature/x
run_engine "$D/A" daily-log/2026-01-15-x.md
[ "$RC" = 3 ] && ok "S13 off main -> exit 3" || bad "S13 off main exit=$RC -- $OUT"
git -C "$D/A" checkout -q main
mkdir -p "$D/A/.git/rebase-merge"
run_engine "$D/A" daily-log/2026-01-15-x.md
[ "$RC" = 2 ] && ok "S13 rebase state present -> exit 2" || bad "S13 pre-flight exit=$RC -- $OUT"
rmdir "$D/A/.git/rebase-merge"


# ---------------------------------------------------------------- S14
say "S14 archive move: both halves of a staged rename on the allow-list"
D=$(mkrepo s14)
( cd "$D/A" && git mv memory/project_p.md memory/archive/project_p.md )
printf 'index v1\n' > "$D/A/memory/MEMORY.md"
run_engine "$D/A" memory/project_p.md memory/archive/project_p.md memory/MEMORY.md
[ "$RC" = 0 ] || bad "S14 exit=$RC expected 0 -- $OUT"
git -C "$D/A" fetch -q origin main
git -C "$D/A" cat-file -e origin/main:memory/project_p.md 2>/dev/null && bad "S14 old path still on origin"
origin_has "$D" memory/archive/project_p.md "project p" && [ "$RC" = 0 ] && ok "S14 rename committed and pushed from the two-path allow-list" || bad "S14 archived file not on origin"


# ---------------------------------------------------------------- S4
say "S4 legitimate co-write upstream on the same file -> exit 0, no false alarm"
D=$(mkrepo s4)
other_pushes "$D" daily-log/shared.md 'line1 BY TWO
line2
line3
line4
line5
'
printf 'line1\nline2\nline3\nline4\nline5 BY ONE\n' > "$D/A/daily-log/shared.md"
run_engine "$D/A" daily-log/shared.md
[ "$RC" = 0 ] || bad "S4 exit=$RC expected 0 -- $OUT"
echo "$OUT" | grep -q "VERIFY OK" || bad "S4 missing VERIFY OK"
origin_has "$D" daily-log/shared.md "line5 BY ONE" && origin_has "$D" daily-log/shared.md "line1 BY TWO" && [ "$RC" = 0 ] \
  && ok "S4 co-write recognised, origin has both sides" || bad "S4 origin content wrong"


# ---------------------------------------------------------------- S6
say "S6 the lost commit: a skip drops the session commit, the push exits 0, the content check must catch it"
D=$(mkrepo s6)
other_pushes "$D" daily-log/shared.md 'line1 BY TWO
line2
line3
line4
line5
'
( cd "$D/A" && printf 'line1 BY ONE\nline2\nline3\nline4\nline5\nsession work\n' > daily-log/shared.md \
  && git add daily-log/shared.md && git commit -qm "session one" )
ORIG_S6="$(git -C "$D/A" rev-parse HEAD)"
# The wrong procedure, replayed on purpose: rebase, hit the conflict, skip, push.
( cd "$D/A" && git fetch -q origin main && git rebase -q origin/main >/dev/null 2>&1; GIT_EDITOR=true git rebase --skip >/dev/null 2>&1; git push -q origin main ) || bad "S6 setup failed"
PUSHED_S6="$(git -C "$D/A" rev-parse HEAD)"
[ "$(git -C "$D/A" rev-parse origin/main)" = "$PUSHED_S6" ] || bad "S6 setup: pushed head should equal origin/main (hash equality would pass here)"
OUT="$(cd "$D/A" && bash scripts/debrief-verify.sh "$ORIG_S6^" "$ORIG_S6" "$PUSHED_S6" daily-log/shared.md 2>&1)"; RC=$?
[ "$RC" = 1 ] || bad "S6 verify exit=$RC expected 1 -- $OUT"
echo "$OUT" | grep -q "line missing" || bad "S6 missing-line detail absent"
echo "$OUT" | grep -q "+session work" || bad "S6 the lost line is not the one reported"
[ "$RC" = 1 ] && ok "S6 lost commit -> PUSH-INCOMPLETE with the missing line named"


# ---------------------------------------------------------------- S9
say "S9 a failing content check -> exit 41 and the reference path"
D=$(mkrepo s9)
printf '#!/usr/bin/env bash\necho "PUSH-INCOMPLETE: stubbed"\nexit 1\n' > "$D/A/scripts/debrief-verify.sh"
printf 'session one\n' > "$D/A/daily-log/2026-01-15-op-one.md"
run_engine "$D/A" daily-log/2026-01-15-op-one.md
[ "$RC" = 41 ] || bad "S9 exit=$RC expected 41 -- $OUT"
echo "$OUT" | grep -q "exit 41: procedure in skills/session-debrief/reference/push-outcomes.md" || bad "S9 reference path not printed"
[ "$RC" = 41 ] && ok "S9 verify failure maps to exit 41 with the reference path"


# ---------------------------------------------------------------- S7
say "S7 index already holds a foreign staged path -> exit 4, nothing committed, stage intact"
D=$(mkrepo s7)
( cd "$D/A" && printf 'edit by ANOTHER session\n' >> base.md && git add base.md )
printf 'session one\n' > "$D/A/daily-log/2026-01-15-op-one.md"
run_engine "$D/A" daily-log/2026-01-15-op-one.md
[ "$RC" = 4 ] || bad "S7 exit=$RC expected 4 -- $OUT"
echo "$OUT" | grep -q "GUARD-INDEX" || bad "S7 missing GUARD-INDEX"
echo "$OUT" | grep -q "^base.md$" || bad "S7 foreign path not named"
[ "$(git -C "$D/A" rev-list --count HEAD)" = 1 ] || bad "S7 something was committed"
git -C "$D/A" diff --cached --name-only | grep -qx "base.md" || bad "S7 foreign stage altered"
[ "$RC" = 4 ] && ok "S7 exit 4: clean stop, foreign stage intact, no commit"


# ---------------------------------------------------------------- S3
say "S3 dirty tree + real conflict -> exit 21, worktree standing, main tree intact"
D=$(mkrepo s3)
other_pushes "$D" daily-log/shared.md 'line1 BY TWO
line2
line3
line4
line5
'
printf 'line1 BY ONE\nline2\nline3\nline4\nline5\n' > "$D/A/daily-log/shared.md"
printf 'wip\n' > "$D/A/areas/notes/wip.md"
run_engine "$D/A" daily-log/shared.md
[ "$RC" = 21 ] || bad "S3 exit=$RC expected 21 -- $OUT"
echo "$OUT" | grep -q "CONFLICT-WORKTREE" || bad "S3 missing CONFLICT-WORKTREE"
echo "$OUT" | grep -q "procedure in skills/session-debrief/reference/push-outcomes.md" || bad "S3 reference path not printed"
WT_S3="$(echo "$OUT" | grep '^worktree: ' | cut -d' ' -f2-)"
[ -n "$WT_S3" ] && [ -d "$WT_S3" ] || bad "S3 worktree not standing ($WT_S3)"
echo "$OUT" | grep -q "^daily-log/shared.md$" || bad "S3 conflicted file not listed"
ORIG_S3="$(echo "$OUT" | grep '^session commit: ' | cut -d' ' -f3)"
[ "$(git -C "$D/A" rev-parse HEAD)" = "$ORIG_S3" ] || bad "S3 main tree HEAD moved"
grep -q "^wip$" "$D/A/areas/notes/wip.md" || bad "S3 WIP touched"
[ "$RC" = 21 ] && [ -d "$WT_S3" ] && ok "S3 exit 21, worktree standing, main tree untouched"
# S3-resolve: the documented procedure, run by hand: resolve inside the worktree,
# continue, push, verify by content.
say "S3-resolve: finish the rebase inside the worktree, then verify"
printf 'line1 BY ONE AND TWO\nline2\nline3\nline4\nline5\n' > "$WT_S3/daily-log/shared.md"
( cd "$D/A" && git -C "$WT_S3" add -- daily-log/shared.md && GIT_EDITOR=true git -C "$WT_S3" rebase --continue >/dev/null 2>&1 \
  && git -C "$WT_S3" push -q origin HEAD:main ) || bad "S3-resolve continuation failed"
OUT="$(cd "$D/A" && bash scripts/debrief-verify.sh "$ORIG_S3^" "$ORIG_S3" - daily-log/shared.md 2>&1)"; RC=$?
# The resolved line differs from the local line by design: verify must report it,
# because the operator chose a merged line and the check cannot know that.
[ "$RC" = 1 ] && echo "$OUT" | grep -q "line1 BY ONE" || bad "S3-resolve verify should flag the merged line as changed -- $OUT"
origin_has "$D" daily-log/shared.md "line1 BY ONE AND TWO" && ok "S3-resolve merged content on origin; verify flags the changed line for the operator to confirm" || bad "S3-resolve merged content not on origin"
( cd "$D/A" && git worktree remove --force "$WT_S3" >/dev/null 2>&1; git worktree prune >/dev/null 2>&1 )


# ---------------------------------------------------------------- S8
say "S8 auto-take is a team option: off by default (exit 21), on -> origin kept and declared"
D=$(mkrepo s8)
other_pushes "$D" daily-log/2026-01-15-op-one.md 'entry 1
entry 2
entry 3
entry 4 BY TWO
'
printf 'entry 1\nentry 2\nentry 3\n' > "$D/A/daily-log/2026-01-15-op-one.md"   # stale strict subset
printf 'wip\n' > "$D/A/areas/notes/wip.md"
run_engine "$D/A" daily-log/2026-01-15-op-one.md
[ "$RC" = 21 ] || bad "S8-off exit=$RC expected 21 (human gate) -- $OUT"
echo "$OUT" | grep -q "AUTO-TAKE" && bad "S8-off resolved on its own"
WT_S8="$(echo "$OUT" | grep '^worktree: ' | cut -d' ' -f2-)"
( cd "$D/A" && git -C "$WT_S8" rebase --abort >/dev/null 2>&1; git worktree remove --force "$WT_S8" >/dev/null 2>&1; git worktree prune >/dev/null 2>&1; git reset -q --keep origin/main )
[ "$RC" = 21 ] && ok "S8-off default keeps the human gate"
# same collision, option on
D=$(mkrepo s8on)
git -C "$D/A" config brain.debrief.autoTake true
other_pushes "$D" daily-log/2026-01-15-op-one.md 'entry 1
entry 2
entry 3
entry 4 BY TWO
'
printf 'entry 1\nentry 2\nentry 3\n' > "$D/A/daily-log/2026-01-15-op-one.md"
printf 'wip\n' > "$D/A/areas/notes/wip.md"
run_engine "$D/A" daily-log/2026-01-15-op-one.md
[ "$RC" = 0 ] || bad "S8-on exit=$RC expected 0 -- $OUT"
echo "$OUT" | grep -q "AUTO-TAKE: daily-log/2026-01-15-op-one.md" || bad "S8-on missing AUTO-TAKE declaration"
origin_has "$D" daily-log/2026-01-15-op-one.md "entry 4 BY TWO" && [ "$RC" = 0 ] && ok "S8-on origin's complete version kept, choice declared" || bad "S8-on origin lost the complete version"
# option on, but unique lines on both sides: still a human decision
D=$(mkrepo s8both)
git -C "$D/A" config brain.debrief.autoTake true
other_pushes "$D" daily-log/shared.md 'line1 BY TWO
line2
line3
line4
line5
'
printf 'line1 BY ONE\nline2\nline3\nline4\nline5\n' > "$D/A/daily-log/shared.md"
printf 'wip\n' > "$D/A/areas/notes/wip.md"
run_engine "$D/A" daily-log/shared.md
[ "$RC" = 21 ] && ! echo "$OUT" | grep -q "AUTO-TAKE" && ok "S8-both unique lines on both sides stay with the human" || bad "S8-both exit=$RC expected 21 without AUTO-TAKE -- $OUT"
WT_S8B="$(echo "$OUT" | grep '^worktree: ' | cut -d' ' -f2-)"
( cd "$D/A" && git -C "$WT_S8B" rebase --abort >/dev/null 2>&1; git worktree remove --force "$WT_S8B" >/dev/null 2>&1; git worktree prune >/dev/null 2>&1 )

# ---------------------------------------------------------------- S10
say "S10 divergence after a worktree push: diagnosed by default, realigned only as a team option"
mk_s10() { # <name>: origin and local touch the same file within three lines of each other:
           # the replay merges cleanly but its diff context changes, so it is not patch-identical
  local d; d=$(mkrepo "$1")
  other_pushes "$d" daily-log/shared.md 'line1
line2
line3 BY TWO
line4
line5
'
  printf 'line1\nline2\nline3\nline4\nline5 BY ONE\n' > "$d/A/daily-log/shared.md"
  printf 'wip\n' > "$d/A/areas/notes/wip.md"
  echo "$d"
}
D=$(mk_s10 s10)
run_engine "$D/A" daily-log/shared.md
[ "$RC" = 0 ] || bad "S10-default exit=$RC expected 0 -- $OUT"
echo "$OUT" | grep -q "LOCAL-MAIN-DIVERGED: local main carries 1 commit" || bad "S10-default diagnosis missing -- $OUT"
echo "$OUT" | grep -q "git reset --keep origin/main" || bad "S10-default realign command not printed"
[ "$(ahead_count "$D")" = 1 ] && ok "S10-default diverged main left as is, diagnosis printed" || bad "S10-default local main was moved without the option"
D=$(mk_s10 s10on)
git -C "$D/A" config brain.debrief.realign true
run_engine "$D/A" daily-log/shared.md
[ "$RC" = 0 ] || bad "S10-on exit=$RC expected 0 -- $OUT"
echo "$OUT" | grep -q "REALIGNED" || bad "S10-on missing REALIGNED"
[ "$(ahead_count "$D")" = 0 ] || bad "S10-on local main still ahead"
grep -q "^wip$" "$D/A/areas/notes/wip.md" && [ "$RC" = 0 ] && ok "S10-on local main on origin/main, WIP kept" || bad "S10-on WIP lost"
D=$(mk_s10 s10blocked)
git -C "$D/A" config brain.debrief.realign true
other_pushes "$D" areas/notes/wip.md 'wip BY TWO
'
run_engine "$D/A" daily-log/shared.md
[ "$RC" = 0 ] || bad "S10-blocked exit=$RC expected 0 -- $OUT"
echo "$OUT" | grep -q "REALIGN-BLOCKED" || bad "S10-blocked missing REALIGN-BLOCKED -- $OUT"
echo "$OUT" | grep -q 'Follow "Realign refused" in skills/session-debrief/reference/push-outcomes.md' || bad "S10-blocked does not point at the Realign refused procedure -- $OUT"
grep -q "^wip$" "$D/A/areas/notes/wip.md" && [ "$(ahead_count "$D")" = 1 ] && ok "S10-blocked overlap refused, WIP and main intact" || bad "S10-blocked WIP or main touched"


# ---------------------------------------------------------------- S11
say "S11 --integrate-only: local commits that never reached origin"
D=$(mkrepo s11)
( cd "$D/A" && printf 'deferred work\n' > daily-log/2026-01-14-op-one.md && git add daily-log && git commit -qm "debrief: deferred" )
other_pushes "$D" other.md 'from two
'
run_engine "$D/A" --integrate-only
[ "$RC" = 0 ] || bad "S11 exit=$RC expected 0 -- $OUT"
echo "$OUT" | grep -q "^PUSHED$" || bad "S11 missing PUSHED"
echo "$OUT" | grep -q "VERIFY OK" || bad "S11 missing VERIFY OK"
origin_has "$D" daily-log/2026-01-14-op-one.md "deferred work" && [ "$RC" = 0 ] && ok "S11 clean tree: rebased in place, pushed, verified" || bad "S11 content not on origin"
BEFORE_HEAD="$(git -C "$D/A" rev-parse HEAD)"
run_engine "$D/A" --integrate-only stray.md
STRAY_RC="$RC"; STRAY_OUT="$OUT"
run_engine "$D/A" --integrate-only
[ "$RC" = 0 ] && echo "$OUT" | grep -q "NOTHING-TO-INTEGRATE" \
  && [ "$STRAY_RC" = 64 ] && echo "$STRAY_OUT" | grep -q "^USAGE:.*stray.md" \
  && [ "$(git -C "$D/A" rev-parse HEAD)" = "$BEFORE_HEAD" ] \
  && ok "S11-none nothing local -> NOTHING-TO-INTEGRATE; stray file argument refused with exit 64, no commit or push" \
  || bad "S11-none exit=$RC -- $OUT"
D=$(mkrepo s11dirty)
( cd "$D/A" && printf 'deferred work\n' > daily-log/2026-01-14-op-one.md && git add daily-log && git commit -qm "debrief: deferred" )
other_pushes "$D" other.md 'from two
'
printf 'wip\n' > "$D/A/areas/notes/wip.md"
run_engine "$D/A" --integrate-only
[ "$RC" = 0 ] && echo "$OUT" | grep -q "PUSHED-VIA-WORKTREE" && grep -q "^wip$" "$D/A/areas/notes/wip.md" \
  && ok "S11-dirty dirty tree: integrated through the worktree, WIP kept" || bad "S11-dirty exit=$RC -- $OUT"

# ---------------------------------------------------------------- S12
say "S12 through the lock wrapper"
D=$(mkrepo s12)
printf 'session one\n' > "$D/A/daily-log/2026-01-15-op-one.md"
OUT="$(cd "$D/A" && scripts/git-locked scripts/debrief-push.sh daily-log/2026-01-15-op-one.md 2>&1)"; RC=$?
[ "$RC" = 0 ] || bad "S12 exit=$RC expected 0 -- $OUT"
[ ! -d "$D/A/.git/brain-git.lock" ] || bad "S12 lock not released"
[ "$RC" = 0 ] && ok "S12 wrapper passes the exit code through and releases the lock"

# ---------------------------------------------------------------- S15
say "S15 debrief-verify.sh checks deletions symmetrically, not just additions"
# Case 1: a deletion-only commit that reaches origin -> VERIFY OK.
D=$(mkrepo s15)
printf 'line1\nline2\nline3\nline4\n' > "$D/A/daily-log/shared.md"
run_engine "$D/A" daily-log/shared.md
[ "$RC" = 0 ] || bad "S15 setup: clean push of the deletion failed -- $OUT"
DEL_OK="$(git -C "$D/A" rev-parse HEAD)"
OUT1="$(cd "$D/A" && bash scripts/debrief-verify.sh "$DEL_OK^" "$DEL_OK" - daily-log/shared.md 2>&1)"; RC1=$?

# Case 2: a deletion-only commit that stays local, never reaching origin (the
# base it was cut from, which still has the removed line) -> PUSH-INCOMPLETE,
# naming the surviving line.
D=$(mkrepo s15b)
( cd "$D/A" && printf 'line1\nline2\nline3\nline4\n' > daily-log/shared.md \
  && git add daily-log/shared.md && git commit -qm "drop a line" )
DEL_BAD="$(git -C "$D/A" rev-parse HEAD)"
OUT2="$(cd "$D/A" && bash scripts/debrief-verify.sh "$DEL_BAD^" "$DEL_BAD" - daily-log/shared.md 2>&1)"; RC2=$?

# Case 3: a line moved within the same file (removed in one place, re-added in
# another) -> still VERIFY OK, the move is not mistaken for a dropped deletion.
D=$(mkrepo s15c)
printf 'line2\nline1\nline3\nline4\nline5\n' > "$D/A/daily-log/shared.md"
run_engine "$D/A" daily-log/shared.md
[ "$RC" = 0 ] || bad "S15 setup: clean push of the move failed -- $OUT"
MOVED="$(git -C "$D/A" rev-parse HEAD)"
OUT3="$(cd "$D/A" && bash scripts/debrief-verify.sh "$MOVED^" "$MOVED" - daily-log/shared.md 2>&1)"; RC3=$?

# Case 4: a unique fence-shaped line ("---") is dropped, never reaching origin
# -> PUSH-INCOMPLETE naming it. Proves the check reads a diff's hunk bodies,
# not its "---"/"+++" file headers: a naive line-prefix match would silently
# drop this removed line because its own content starts with "---".
D=$(mkrepo s15d)
printf 'alpha\n---\nbeta\ngamma\n' > "$D/A/daily-log/shared.md"
run_engine "$D/A" daily-log/shared.md
[ "$RC" = 0 ] || bad "S15 setup: push of the fence-line base failed -- $OUT"
FENCE_BASE="$(git -C "$D/A" rev-parse HEAD)"
( cd "$D/A" && printf 'alpha\nbeta\ngamma\n' > daily-log/shared.md \
  && git add daily-log/shared.md && git commit -qm "drop the fence line" )
FENCE_LOCAL="$(git -C "$D/A" rev-parse HEAD)"
OUT4="$(cd "$D/A" && bash scripts/debrief-verify.sh "$FENCE_BASE" "$FENCE_LOCAL" - daily-log/shared.md 2>&1)"; RC4=$?

# Case 5: alongside a genuine, checkable edit, one of two identical lines is
# also dropped, and the push landed for real -> VERIFY OK, not a false
# PUSH-INCOMPLETE. Proves a removed line is only checked when it occurred
# exactly once before the change and zero times after: the surviving twin of
# the deleted line must not be read as proof that the deletion failed, as
# long as the range has other content the check can confirm (an all-ambiguous
# range is case 6 below, and is a different, correctly negative, outcome).
D=$(mkrepo s15e)
printf 'alpha\n```\ncodeA\n```\nomega\n' > "$D/A/daily-log/shared.md"
run_engine "$D/A" daily-log/shared.md
[ "$RC" = 0 ] || bad "S15 setup: push of the duplicate-fence base failed -- $OUT"
DUP_BASE="$(git -C "$D/A" rev-parse HEAD)"
printf 'alpha renamed\n```\ncodeA\nomega\n' > "$D/A/daily-log/shared.md"
run_engine "$D/A" daily-log/shared.md
[ "$RC" = 0 ] || bad "S15 setup: push of the duplicate-fence drop failed -- $OUT"
DUP_LOCAL="$(git -C "$D/A" rev-parse HEAD)"
OUT5="$(cd "$D/A" && bash scripts/debrief-verify.sh "$DUP_BASE" "$DUP_LOCAL" - daily-log/shared.md 2>&1)"; RC5=$?

# Case 6: a range whose only change is removing two duplicate fence lines,
# and nothing else, never reaching origin -> PUSH-INCOMPLETE, not a false
# VERIFY OK. Both removed lines fail the uniqueness test on their own (each
# occurs twice before the change), so this range has nothing the content
# check can confirm; printing success there would be the same false green
# light the whole check exists to prevent.
D=$(mkrepo s15f)
printf -- '---\nline1\nline2\nline3\nline4\n---\n' > "$D/A/daily-log/shared.md"
run_engine "$D/A" daily-log/shared.md
[ "$RC" = 0 ] || bad "S15 setup: push of the double-fence base failed -- $OUT"
NOCHK_BASE="$(git -C "$D/A" rev-parse HEAD)"
( cd "$D/A" && printf 'line1\nline2\nline3\nline4\n' > daily-log/shared.md \
  && git add daily-log/shared.md && git commit -qm "drop both fence lines, nothing else" )
NOCHK_LOCAL="$(git -C "$D/A" rev-parse HEAD)"
OUT6="$(cd "$D/A" && bash scripts/debrief-verify.sh "$NOCHK_BASE" "$NOCHK_LOCAL" - daily-log/shared.md 2>&1)"; RC6=$?

# Case 7: a genuinely empty range (<from> and <to> identical) -> still a
# clean VERIFY OK / exit 0. Nothing here to disturb: there is no change at
# all to fail to confirm. Distinct from S11-none, which covers
# --integrate-only's own "nothing local" short-circuit inside
# debrief-push.sh and never reaches debrief-verify.sh; this checks the
# verifier's own empty-range behaviour directly.
OUT7="$(cd "$D/A" && bash scripts/debrief-verify.sh "$NOCHK_LOCAL" "$NOCHK_LOCAL" - daily-log/shared.md 2>&1)"; RC7=$?

# Case 8: a range whose only change is removing a blank line, never reaching
# origin -> PUSH-INCOMPLETE, not a false VERIFY OK. A blank line is skipped
# by every content check (it proves nothing either way), but it must still
# count as touching the file: deciding that from the blank-filtered lines
# would make this range indistinguishable from one nothing touched at all.
D=$(mkrepo s15g)
printf 'alpha\n\nbeta\n' > "$D/A/daily-log/shared.md"
run_engine "$D/A" daily-log/shared.md
[ "$RC" = 0 ] || bad "S15 setup: push of the blank-line base failed -- $OUT"
BLANK_BASE="$(git -C "$D/A" rev-parse HEAD)"
( cd "$D/A" && printf 'alpha\nbeta\n' > daily-log/shared.md \
  && git add daily-log/shared.md && git commit -qm "drop the blank line, nothing else" )
BLANK_LOCAL="$(git -C "$D/A" rev-parse HEAD)"
OUT8="$(cd "$D/A" && bash scripts/debrief-verify.sh "$BLANK_BASE" "$BLANK_LOCAL" - daily-log/shared.md 2>&1)"; RC8=$?

# Case 9: a range whose only change is adding a binary file, never reaching
# origin -> PUSH-INCOMPLETE, not a false VERIFY OK. A binary diff renders no
# "@@" hunk at all, so there is nothing line-based to examine; TOUCHED must
# still come from loop membership (this file came out of the name-only diff,
# so it was unquestionably touched), not from counting hunk-body lines that
# never existed to begin with.
D=$(mkrepo s15h)
BASE_HEAD="$(git -C "$D/A" rev-parse HEAD)"
printf 'a\000b\000c' > "$D/A/blob.bin"
( cd "$D/A" && git add blob.bin && git commit -qm "add a binary file, nothing else" )
BIN_LOCAL="$(git -C "$D/A" rev-parse HEAD)"
OUT9="$(cd "$D/A" && bash scripts/debrief-verify.sh "$BASE_HEAD" "$BIN_LOCAL" - blob.bin 2>&1)"; RC9=$?

# Case 10: an end of the range that does not name a commit -> exit 64, and no
# verdict at all. git refuses to diff such a range, so the file list comes back
# empty and every count stays at zero, which without this guard reads as "an
# empty range, nothing to verify" and prints VERIFY OK on a range that was
# never examined. Callers discard work on that verdict, so it has to be a usage
# error: the absence of VERIFY OK matters as much as the code here.
OUT10="$(cd "$D/A" && bash scripts/debrief-verify.sh nosuchref^ nosuchref - 2>&1)"; RC10=$?

[ "$RC1" = 0 ] && echo "$OUT1" | grep -q "VERIFY OK" \
  && [ "$RC2" = 1 ] && echo "$OUT2" | grep -q "line not removed" && echo "$OUT2" | grep -q -- "-line5" \
  && [ "$RC3" = 0 ] && echo "$OUT3" | grep -q "VERIFY OK" \
  && [ "$RC4" = 1 ] && echo "$OUT4" | grep -q "line not removed" && echo "$OUT4" | grep -q -- "----" \
  && [ "$RC5" = 0 ] && echo "$OUT5" | grep -q "VERIFY OK" \
  && [ "$RC6" = 1 ] && echo "$OUT6" | grep -q "nothing in this range could be confirmed" \
  && [ "$RC7" = 0 ] && echo "$OUT7" | grep -q "VERIFY OK" \
  && [ "$RC8" = 1 ] && echo "$OUT8" | grep -q "nothing in this range could be confirmed" \
  && [ "$RC9" = 1 ] && echo "$OUT9" | grep -q "nothing in this range could be confirmed" \
  && [ "$RC10" = 64 ] && echo "$OUT10" | grep -q "does not name a commit" \
  && ! echo "$OUT10" | grep -q "VERIFY OK" \
  && ok "S15 deletion reaching origin -> VERIFY OK; deletion dropped on the way -> PUSH-INCOMPLETE naming the line; moved line -> no false alarm; a '---' fence line is read from the hunk body, not mistaken for a diff header; a duplicate line's surviving twin does not trigger a false alarm; an unconfirmable range reports PUSH-INCOMPLETE rather than a false VERIFY OK; an empty range still exits 0 cleanly; a blank-line-only range is touched, not empty, and reports PUSH-INCOMPLETE too; a binary-only range is touched, not empty, and reports PUSH-INCOMPLETE too; a range whose end does not name a commit is a usage error (exit 64), never a VERIFY OK on nothing examined" \
  || bad "S15 case1 rc=$RC1 $OUT1 / case2 rc=$RC2 $OUT2 / case3 rc=$RC3 $OUT3 / case4 rc=$RC4 $OUT4 / case5 rc=$RC5 $OUT5 / case6 rc=$RC6 $OUT6 / case7 rc=$RC7 $OUT7 / case8 rc=$RC8 $OUT8 / case9 rc=$RC9 $OUT9 / case10 rc=$RC10 $OUT10"

# ---------------------------------------------------------------- S16
say "S16 clean tree, origin advances between fetch and push -> exit 40, commit safe"
D=$(mkrepo s16)
# A pre-push hook lets operator two land a commit after the engine's fetch and
# before its push. That is the race itself: the push is then refused as a
# non-fast-forward, on the plain main-tree path rather than the worktree one.
cat > "$D/A/.git/hooks/pre-push" <<HOOK
#!/usr/bin/env bash
[ -f "$D/raced" ] && exit 0
touch "$D/raced"
( cd "$D/B" && git pull -q --rebase origin main && printf 'from two\n' > raced.md \
  && git add raced.md && git commit -qm "two: raced.md" && git push -q origin main ) >/dev/null 2>&1
exit 0
HOOK
chmod +x "$D/A/.git/hooks/pre-push"
printf 'session one\n' > "$D/A/daily-log/2026-01-15-op-one.md"
run_engine "$D/A" daily-log/2026-01-15-op-one.md
[ "$RC" = 40 ] || bad "S16 exit=$RC expected 40 -- $OUT"
echo "$OUT" | grep -q "^PUSH-RACE:" || bad "S16 missing PUSH-RACE marker"
echo "$OUT" | grep -q "push-outcomes.md" || bad "S16 the reference path was not printed"
git -C "$D/A" log -1 --format=%s | grep -q "^debrief: " || bad "S16 the session commit was not kept locally"
origin_has "$D" daily-log/2026-01-15-op-one.md "session one" && bad "S16 the refused push landed anyway"
[ "$(ahead_count "$D")" = 1 ] || bad "S16 local main is not one commit ahead of origin"
[ "$RC" = 40 ] && ok "S16 a refused push from the main tree exits 40, the commit stays local, origin is untouched" \
  || bad "S16 wrong outcome"


say "RESULT: PASS=$PASS FAIL=$FAIL"
rm -rf "$BASE"
[ "$FAIL" = 0 ]
