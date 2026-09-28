# Push outcomes: the exit codes of `scripts/debrief-push.sh`

Reference for `session-debrief` (Step 5) and `sync` (Step 4). Open it when the engine
exits with a code other than 0: the script prints this path on every such exit. The
common outcomes (`PUSHED`, `PUSHED-VIA-WORKTREE`, `LOCAL-ONLY`, exit 75) are described
in the skills themselves and repeated here for completeness.

**Maintenance rule:** the script and this table share the exit codes. A code changes
in both places in the same commit, never in one. `scripts/tests/test-skill-snippets.sh`
fails when they drift.

Only the codes below are legitimate outcomes. Anything else (a `1`, a `127`, a shell
syntax error) is an anomaly in how the script was run: stop, investigate the command
itself, and do not map it onto a row here.

## The lock

Every invocation goes through `scripts/git-locked`, which serializes git operations
between parallel sessions on the same clone (one lock per repository, held for the
duration of the wrapped command, broken only when its owner process is gone, it is
older than ten minutes, and no merge or rebase is in progress). Documented exception:
from a session isolated in its own git worktree, some agent harnesses refuse a command
line that names git more than once (the wrapper plus the wrapped command). In that
case, and only there, run the wrapped command without the wrapper: work confined to
your own branch has near-zero contention. Never push to `main` unlocked.

## exit 0

**`PUSHED`**: committed, integrated, pushed, and verified by content: every line the
local commits added or removed is reflected on `origin/main`.

**`PUSHED-VIA-WORKTREE`**: same, through a temporary worktree, because the main tree
held uncommitted work, which was never touched. One of these follow-up lines may
appear:

- `LOCAL-MAIN-DIVERGED: local main carries N commit(s) whose content is on origin
  under different hashes.` Local `main` still points at the pre-rebase commits. Their
  content is on origin (just verified) but not their patch identity, so **the next
  rebase would not drop them as duplicates: it would replay them as spurious
  conflicts**, and whoever resolves those by "keeping mine" regresses content written
  by others. Do not rebase. Realign with:

  ```bash
  scripts/git-locked git reset --keep origin/main
  ```

  `--keep` preserves uncommitted work on files the move does not touch and refuses,
  changing nothing, when it would touch one; on a refusal, follow "Realign refused"
  below. Note in the log: "local main was N ahead, realigned".
- `REALIGNED` / `REALIGN-BLOCKED`: the team option `brain.debrief.realign` is on and
  the engine ran the reset itself. `REALIGN-BLOCKED` means the reset refused because
  uncommitted work overlaps a file it would change: nothing was touched. Follow
  "Realign refused" below.
- `AUTO-TAKE: <file> -> origin side kept`: the team option `brain.debrief.autoTake`
  is on and a conflict was resolved by taking origin, because every line of the local
  side already existed there. Nothing was lost by construction. `SKIP-EMPTY` after it
  means the session commit held nothing else and was dropped as empty.
- Nothing: the replay was patch-identical and the next `/sync` drops it cleanly.

### Realign refused

`reset --keep` refused (`REALIGN-BLOCKED`, or the manual reset above, or the one
`/sync` proposes). Do not leave it there: until local `main` realigns, every debrief
takes the temporary-worktree route again and the divergence grows. Do not improvise
a checkout or a reset by hand either. Two steps.

**1. Name the blockers** (writes nothing but git's own index refresh). A blocker is a
path the move would change that also holds uncommitted work: a tracked file with
staged or unstaged edits, or an untracked file where origin adds one. Each is then
compared with `origin/main` byte for byte, and its staged copy too: a staged version
that matches neither `HEAD` nor origin is work of its own, even when the working copy
matches origin:

```bash
cd "$(git rev-parse --show-toplevel)"
scripts/git-locked bash -c '
  git update-index -q --refresh >/dev/null 2>&1 || true
  BLOCKERS="$( { comm -12 <(git -c core.quotePath=false diff --name-only HEAD | LC_ALL=C sort -u) \
                          <(git -c core.quotePath=false diff --name-only HEAD origin/main | LC_ALL=C sort -u)
                 comm -12 <(git -c core.quotePath=false ls-files --others | LC_ALL=C sort -u) \
                          <(git -c core.quotePath=false diff --name-only --diff-filter=A HEAD origin/main | LC_ALL=C sort -u)
               } | LC_ALL=C sort -u)"
  if [ -z "$BLOCKERS" ]; then echo "NO BLOCKER: nothing in the tree overlaps the move; rerun the reset"; exit 0; fi
  LIVE=0
  while IFS= read -r f; do
    if [ -e "$f" ]; then have="$(git hash-object -- "$f")"; else have=absent; fi
    want="$(git rev-parse -q --verify "origin/main:$f" 2>/dev/null || echo absent)"
    idx="$(git ls-files -s -- "$f" | cut -d" " -f2)"
    inhead="$(git rev-parse -q --verify "HEAD:$f" 2>/dev/null || echo absent)"
    if [ "$have" = "$want" ] && { [ -z "$idx" ] || [ "$idx" = "$want" ] || [ "$idx" = "$inhead" ]; }; then
      echo "RELEASABLE: $f"; else echo "LIVE WORK: $f"; LIVE=1; fi
  done <<< "$BLOCKERS"
  if [ "$LIVE" = 0 ]; then echo "ALL RELEASABLE"; else echo "LIVE WORK PRESENT: release nothing"; fi
'
```

**2. Act on the verdict.**

- `LIVE WORK: <file>`: the file differs from origin, so it is genuine uncommitted
  work, most often another session's. It stays exactly as it is. Nothing is
  released, not even the releasable files next to it (the reset would still refuse).
  Name **that file** in the daily log as the reason local `main` is still diverged;
  the realignment waits until its owner commits it.
- `ALL RELEASABLE`: every blocker already holds exactly what origin holds (typically
  content that reached origin through a temporary-worktree push and was left behind
  in the tree). Moving `main` changes no byte of it. Show the list and ask the
  operator for an explicit ok; only then run the release. It rechecks every blocker
  under the lock, records its hash, sets it aside, resets, and compares each file
  with its recorded hash after the move; if the reset still refuses, it puts every
  file back with the content it had (origin's, by the check above):

  ```bash
  cd "$(git rev-parse --show-toplevel)"
  scripts/git-locked bash -c '
    git update-index -q --refresh >/dev/null 2>&1 || true
    BLOCKERS="$( { comm -12 <(git -c core.quotePath=false diff --name-only HEAD | LC_ALL=C sort -u) \
                            <(git -c core.quotePath=false diff --name-only HEAD origin/main | LC_ALL=C sort -u)
                   comm -12 <(git -c core.quotePath=false ls-files --others | LC_ALL=C sort -u) \
                            <(git -c core.quotePath=false diff --name-only --diff-filter=A HEAD origin/main | LC_ALL=C sort -u)
                 } | LC_ALL=C sort -u)"
    [ -n "$BLOCKERS" ] || { echo "NO BLOCKER: rerun the reset"; exit 0; }
    REC="$(mktemp)"; trap "rm -f \"$REC\"" EXIT
    while IFS= read -r f; do
      if [ -e "$f" ]; then have="$(git hash-object -- "$f")"; else have=absent; fi
      want="$(git rev-parse -q --verify "origin/main:$f" 2>/dev/null || echo absent)"
      idx="$(git ls-files -s -- "$f" | cut -d" " -f2)"
      inhead="$(git rev-parse -q --verify "HEAD:$f" 2>/dev/null || echo absent)"
      [ "$have" = "$want" ] || { echo "STOP: $f differs from origin/main; nothing released"; exit 30; }
      [ -z "$idx" ] || [ "$idx" = "$want" ] || [ "$idx" = "$inhead" ] || { echo "STOP: $f has staged content of its own; nothing released"; exit 30; }
      echo "$have $f" >> "$REC"
    done <<< "$BLOCKERS"
    while IFS= read -r f; do
      if git cat-file -e "HEAD:$f" 2>/dev/null; then git checkout -q HEAD -- "$f"
      else git rm -q --cached --ignore-unmatch -- "$f"; rm -f -- "$f"; fi
    done <<< "$BLOCKERS"
    if ! git reset -q --keep origin/main; then
      while IFS= read -r f; do
        if git cat-file -e "origin/main:$f" 2>/dev/null; then git show "origin/main:$f" > "$f"; else rm -f -- "$f"; fi
      done <<< "$BLOCKERS"
      echo "STOP: the reset still refused; every blocker was put back with its origin content"; exit 30
    fi
    BAD=""
    while read -r before f; do
      if [ -e "$f" ]; then now="$(git hash-object -- "$f")"; else now=absent; fi
      [ "$now" = "$before" ] || BAD="$BAD $f"
    done < "$REC"
    if [ -z "$BAD" ]; then echo "REALIGNED: local main on origin/main; released files unchanged byte for byte"
    else echo "MISMATCH after realign:$BAD"; exit 30; fi
  '
  ```

  Note in the log: "local main realigned; released: <files>". A `STOP` or a
  `MISMATCH` means the realignment did not happen cleanly: show the output and
  stop there.

**`LOCAL-ONLY`**: no `origin` remote; the commit is kept locally. Finish `SETUP.md`.

**`NOTHING-TO-INTEGRATE`** (`--integrate-only` only): origin already holds every
local commit; nothing to push.

## exit 2

`PRE-FLIGHT FAIL`: a merge or rebase was already in progress before this run,
probably left stopped by an earlier session. Nothing was committed. Show it to the
operator (`git status`) and stop: an unfinished integration is a state to understand,
not to push past.

## exit 3

`GUARD`: `HEAD` is not on `main`. Nothing was committed. Usually a feature branch: go
back to the branch guard in `session-debrief` Step 0 (branch work committed in its
worktree, daily log and memory debriefed from the main tree on `main`). Check for
a stopped rebase too (`git status`): a rebase in progress leaves `HEAD` detached, which
trips this guard before the pre-flight can report it.

## exit 4

`GUARD-INDEX`: the index already held staged paths outside the allow-list (listed in
the output). They are another session's work: a plain commit would have swept them
in. Nothing was committed and the staged content is intact. Two ways forward, both
decided in chat: wait for the session that staged them to commit, or unstage them with
the operator's explicit ok (`git restore --staged <path>` keeps the file content on
disk), then rerun. Never unstage silently.

## exit 10

`DEFER`: the temporary worktree could not be created, so the push is postponed. The
commit is safe locally. Also the outcome when an operator explicitly gives up on an
exit 21 (see there). Note in the log: "local main ahead by N, integrate at the next
`/sync`".

## exit 20

`CONFLICT`: the rebase in the **main tree** (the tree was clean, so no worktree was
used) stopped on a conflict. It is not aborted and nothing is lost; it is waiting for
a decision. Resolve it now, in this session, inside the rebase.

First check `git status --porcelain` for unmerged (`UU`) paths. If there are none and
`.git/rebase-merge` does not exist, no rebase ever started: a local untracked file
blocks an incoming file at the same path. The protocol below does not apply; decide in
chat (typically move the local file aside with the operator's ok, then rerun).

1. List the conflicted files. Show the operator both sides: yours is
   `git show REBASE_HEAD:<file>`, theirs is `git show HEAD:<file>` (during a rebase
   `HEAD` is the origin side, which reads backwards until you have seen it once).
2. Before treating it as a disagreement, rule out a conflict that is not one. When
   local `main` was left diverged by an earlier `PUSHED-VIA-WORKTREE` and never
   realigned, this rebase replays commits whose content is already on origin under
   different hashes: they do not drop as duplicates, they surface here as conflicts,
   and "keeping mine" regresses whatever was written on top of them since. Prove it by
   content, never by hash, subject, or gut.

   The question is not whether the two sides of the conflict differ: a rebase only
   stops on a file when they do, so that answer is always yes and settles nothing. The
   question is whether the commit being replayed adds or removes anything
   `origin/main` does not already hold, which is exactly what
   `scripts/debrief-verify.sh` answers. Inside a stopped rebase that commit is
   `REBASE_HEAD`, and this rebase is running in the main tree, the one you are in, so
   it is read directly, with no `-C`. The verifier fetches internally, so the check
   goes through the lock:

   ```bash
   scripts/git-locked bash -c '
     set -e
     RH="$(git rev-parse --verify REBASE_HEAD)"
     PARENT="$(git rev-parse --verify "$RH^")"
     scripts/debrief-verify.sh "$PARENT" "$RH" -
   '
   ```

   Both ends of the range are resolved into variables before the check runs, and
   `set -e` stops the block if either fails. That is not decoration: handed a range it
   cannot resolve, the verifier finds no file changed and reports success on nothing,
   which here would read as permission to discard the commit.

   `VERIFY OK` means every line that commit adds is already on origin and every line
   it removes is already gone there: the conflict is spurious, and the resolution is
   to take theirs in full. The commit then holds nothing origin does not already have
   and becomes empty, and step 3 below ends it with the skip it describes for exactly
   that case. **Never skip the session commit** (the sha the engine printed): it is
   the only place the work just done lives, so its content can never already be on
   origin.

   `PUSH-INCOMPLETE` means that commit carries content origin does not have: a real
   disagreement, to resolve on its merits. The resolution is then the operator's
   explicit choice: mine, theirs, or both merged. Never resolve silently, never pick
   for them. For two index lines in `memory/MEMORY.md` the answer is almost always the
   union: both lines are true, keep both (`memory/CLAUDE.md`, "When two debriefs
   collide").
3. Apply the resolution with the Edit tool, removing the markers, then close the
   rebase with a targeted `add`. Never `git add -A`, never `commit -a`, never
   `--amend`: each sweeps in files this session did not write.

   ```bash
   scripts/git-locked bash -c '
     set -e
     git add -- <only-the-conflicted-files>
     git update-index -q --ignore-submodules --refresh || true
     if ! git diff-files --quiet; then
       echo "STOP: unstaged changes present in the tree; not forcing, not aborting. Decide in chat."; exit 30
     fi
     GIT_EDITOR=true git rebase --continue
     git push origin main
   '
   ```

   `git rebase --continue` refuses while any tracked file is unstaged, and
   `git rebase --abort` would hard-reset those edits out of existence. On `STOP`
   (exit 30) do neither: leave the rebase stopped, say which files are dirty, decide
   in chat.

   If the continue reports that the commit became empty, because the resolution took
   "theirs" in full and the commit held nothing else, finish with
   `scripts/git-locked bash -c "GIT_EDITOR=true git rebase --skip && git push origin main"`.
   That is the only legitimate skip here. **`--skip` is never the fallback of a failed
   `--continue`:** the exit code of `--continue` does not distinguish "still stopped on
   this conflict" from "advanced and stopped on the next commit", and a
   `--continue || --skip` throws away good commits with the push still exiting 0.
4. After the push, verify by content. The range is every local commit the push
   carried, not just the session one: `pull --rebase` leaves the pre-rebase head in
   `ORIG_HEAD`, and whatever an earlier run deferred went out with it. The verifier
   fetches internally, so it goes through the lock:

   ```bash
   scripts/git-locked scripts/debrief-verify.sh "$(git merge-base ORIG_HEAD origin/main)" ORIG_HEAD -
   ```

   A line you rewrote while resolving is reported as missing: that is expected for
   exactly those lines and nothing else. Any other reported line is lost work: treat it
   as exit 41.
5. Another conflict at the continue: repeat from 1. Two retries at most, then the safe
   abort below and `DEFER`.
6. No immediate resolution (the operator stepped away, the case is ambiguous): safe
   abort at once and `DEFER`. Never leave a rebase suspended past the session: the next
   session's pre-flight refuses to run and nobody remembers why.

**Safe abort**, the only permitted way to abort a rebase in the main tree. A bare
`git rebase --abort` hard-resets **every** unstaged change in the tree, including
in-progress work of a parallel session that has nothing to do with the conflict. The
guard excludes the conflicted paths themselves (those are what the abort is supposed
to reset) and counts everything else:

```bash
scripts/git-locked bash -c '
  set -e
  git update-index -q --ignore-submodules --refresh || true
  DIRTY="$(comm -23 <(git diff-files --name-only | LC_ALL=C sort -u) <(git ls-files --unmerged | cut -f2 | LC_ALL=C sort -u))"
  if [ -n "$DIRTY" ]; then
    echo "STOP: aborting would destroy unstaged changes in:"; echo "$DIRTY"
    echo "Save that content first (explicit decision in chat), then rerun."; exit 30
  fi
  git rebase --abort
  echo "DEFER: rebase aborted cleanly, local commit kept"; exit 10
'
```

## exit 21

`CONFLICT-WORKTREE`: the main tree held uncommitted work, so the rebase ran in a
temporary worktree, and it stopped on a conflict there. **It was not aborted and the
worktree is still standing**; the main tree was never touched, so parallel work is
safe by construction. The output names the worktree (`worktree: <path>`), the session
commit (`session commit: <sha>`), and the conflicted files, which are the whole
residue: if the team option `brain.debrief.autoTake` is on, the mechanical ones were
already taken and declared with `AUTO-TAKE:` lines.

1. Show both sides: mine is `git -C "<path>" show REBASE_HEAD:<file>`, theirs is
   `git -C "<path>" show HEAD:<file>`.
2. Before treating it as a disagreement, run the check in step 3: it tells a spurious
   conflict, whose content is already on origin, from a real one. For a real one the
   resolution is the operator's explicit choice (mine, theirs, merged); never silent.
3. Edit the file **inside the worktree** (`<path>/<file>`, markers removed), then
   close under the lock with a targeted add. Run it from the root of the main repo:
   `git worktree remove` resolves against the repo it starts from.

   ```bash
   scripts/git-locked bash -c '
     set -e
     WT=<path-of-the-worktree>
     git -C "$WT" add -- <only-the-conflicted-files>
     GIT_EDITOR=true git -C "$WT" rebase --continue
     git -C "$WT" push origin HEAD:main
     git worktree remove --force "$WT"
     git worktree prune
     rm -rf "$(dirname "$WT")"
   '
   ```

   Two skips only are legitimate, and neither is a fallback of a failed `--continue`:
   a commit that became empty because you took "theirs" in full (git itself asks for
   the skip), and a commit whose content is already on origin, **proven by content**,
   never by hash, subject, or gut. Whether the two sides of the conflict differ proves
   nothing (a rebase only stops when they do); whether the commit being replayed adds
   or removes anything `origin/main` does not already hold is the question, and
   `scripts/debrief-verify.sh` answers it. The stopped rebase lives in the worktree, so
   `REBASE_HEAD` is read there with `-C`; the check itself runs from the root of the
   main repo, which shares the same objects and the same `origin/main`:

   ```bash
   scripts/git-locked bash -c '
     set -e
     WT=<path-of-the-worktree>
     RH="$(git -C "$WT" rev-parse --verify REBASE_HEAD)"
     PARENT="$(git rev-parse --verify "$RH^")"
     scripts/debrief-verify.sh "$PARENT" "$RH" -
   '
   ```

   Both ends of the range are resolved into variables before the check runs, and
   `set -e` stops the block if either fails: handed a range it cannot resolve, the
   verifier finds no file changed and reports success on nothing, which here would read
   as permission to skip the commit.

   `VERIFY OK`: the conflict is spurious, take theirs in full; the commit becomes empty
   and the skip above is the legitimate one. `PUSH-INCOMPLETE`: that commit carries work
   origin does not have, so it is a real disagreement, resolved on its merits and never
   skipped. **Never skip the session commit** (the sha the engine printed): it is the
   only place the work just done lives.
4. After the push, verify by content, exactly as in exit 20 step 4, with one
   difference: the main tree was never rebased, so its own `HEAD` is still the
   pre-rebase head and takes the place of `ORIG_HEAD`.

   ```bash
   scripts/git-locked scripts/debrief-verify.sh "$(git merge-base HEAD origin/main)" HEAD -
   ```

   Then read the outcome as `PUSHED-VIA-WORKTREE`: local `main` is now diverged, follow
   the `LOCAL-MAIN-DIVERGED` procedure under exit 0.
5. Another conflict at the continue: repeat from 1, two retries at most.
6. Giving up is safe here and needs no guard: the worktree is disposable and holds
   nobody's work in progress, so aborting cannot destroy anything.
   `scripts/git-locked bash -c 'WT=<path>; git -C "$WT" rebase --abort; git worktree remove --force "$WT"; git worktree prune; rm -rf "$(dirname "$WT")"'`
   then report `DEFER` (exit 10) with a note in the log.

## exit 30

`STOP`, from the guards inside the exit 20 procedure: a parallel session dirtied the
tree while the rebase was stopped. Force nothing: the rebase stays stopped (the
pre-flight protects it), the other session's work stays on disk. Explicit decision in
chat, usually: get that content to safety (whoever wrote it knows what it is), then
rerun the continuation or the safe abort.

## exit 40

`PUSH-RACE`: origin advanced in the seconds between the fetch and the push, so the
push was refused. Both push paths end here: the one from the temporary worktree, taken
when the main tree held uncommitted work, and the plain one from the main tree, taken
when it did not. Either way nothing is lost and nothing gets forced: the commit is safe
locally and the working tree is where it was. Rerun the debrief's engine (or `/sync`,
which integrates it); the rerun fetches the commit that won the race and replays this
one on top of it. Two in a row is worth mentioning to the operator: sessions are
closing on top of each other.

A push refused for another reason lands here too, since the code is read off the
refusal and not off its cause: no credentials for the remote, a pre-receive hook that
rejected the branch, a protection rule on `main`. The remedy is the same either way,
which is why the code is: rerun, and if the second run is refused identically, read
git's own message on the failed push, because that is where the difference between a
race and a closed door is stated.

## exit 41

`PUSH-INCOMPLETE`: the push succeeded, and yet a change made by one of the local
commits it carried is not confirmed on `origin/main`, in one of three shapes, described
in the output. The verified range starts at the fork point, so the commit that made the
change may be the session commit or one an earlier run left behind:

- a line it added is missing there;
- a line it removed, or a whole file it deleted, is still there;
- nothing in the range could be confirmed by content, because every change it made was
  of a shape this check cannot read: a binary file, a mode-only change, a blank line,
  or a removed line that repeats elsewhere in its file. None of them could be confirmed
  either way; printing success on nothing checked would be the same false green light
  as the other two shapes.

A rebase dropped a commit on the way, or a resolution took the other side. Nothing is
lost: the work is in the local commits and on disk. **Never close the session on this
outcome**: it is the exact window in which the system would declare a false success.

For the first two shapes, re-apply the dropped change with a targeted cherry-pick of
the commit the output points at: it names the file and the line, so identify the commit
in the verified range that added or removed it and re-send that one, through the
engine's `--integrate-only` path if the tree allows, otherwise by hand under the lock.
It is often the session commit (`session commit: <sha>` in the output), but picking
that one restores nothing when the line belongs to an earlier commit riding the same
push. Then rerun the check until it says `VERIFY OK`:

```bash
scripts/git-locked scripts/debrief-verify.sh "$(git merge-base HEAD origin/main)" HEAD -
```

If the dropped commit cannot be identified: for a missing addition or a surviving
removed line, commit the affected paths again from the files on disk, which already
reflect the intended change, and push that; for a whole file that should have been
deleted but is still on origin, there is no file left on disk to commit from, so stage
the deletion again (`git rm <path>`) and push that instead.

For the third shape, the push may already have landed; the check simply cannot confirm
it by content. Retry the push (harmless if the content is already there) and rerun the
check. If it keeps reporting the same shape, compare the file by hand: content this
check cannot confirm is not the same as content proven missing.

## exit 50

`FETCH FAILED`: origin could not be reached, so nothing was fetched, integrated or
pushed. The commit was already made and stays exactly where it is; the working tree was
never touched. This is the ordinary offline outcome, not a fault of the session: report
it as it came out, note in the log that the work is committed locally and goes out at
the next `/sync`, and never retry in a silent loop.

The same code covers a remote that answers but has no `main` branch yet, which is a
brain whose first push never happened: finish `SETUP.md` instead of rerunning. If the
network is up and the remote is initialised, the problem is the remote itself, not the
session: check it (`git remote -v`, `git ls-remote origin`) before drawing any
conclusion about the commit.

## exit 64

`USAGE`: no file received, a directory received, a path that is neither on disk nor
known to git, or an allow-list with nothing to commit. Nothing was committed. Fix the
invocation (one quoted file per argument) and rerun.

## exit 65

`IDENTITY ERROR`: `git config user.name` is empty or does not match exactly one file
in `operators/`. Nothing was committed. Fix the identity or the registry
(`operators/CLAUDE.md`), then rerun.

## exit 75

The lock is held by another live session. Retry on a later tool turn; never remove
the lock by hand, and never bypass the wrapper for a push to `main`.

If a push fails on a network error, the commit stays, the log records it, and there is
no silent retry.
