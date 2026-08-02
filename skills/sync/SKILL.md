---
name: sync
description: |
  Manual workspace alignment: fetch origin, fast-forward main, and report anything
  that diverged. It aligns and explains; it never resolves a conflict on its own.
  Use when the operator says: sync, /sync, pull, fetch, refresh workspace, pull main.
---

# Sync

Run this at the start of a session, before branching off `main` for new work, and any
time you suspect a teammate pushed since you last pulled. It answers one question in
plain language: is my copy of the brain the same as everyone else's, and if not, what
exactly is different?

Sync is deliberately conservative. It fast-forwards when that is safe, it proposes a
command when the decision is the operator's, and it stops rather than guessing whenever
the two histories have genuinely diverged. It never stashes, never force-pushes, and
never resolves a conflict without the operator choosing the resolution.

Run the steps in order.

---

## Step 0: Resolve the operator

Sync is usually the first thing a session runs, which makes it the first place a
misconfigured identity shows up. That is a feature: better to fail here, on a read-only
routine, than three hours later inside a debrief that is trying to write a daily log
under a slug that does not exist.

```bash
cd "$(git rev-parse --show-toplevel)"
GIT_NAME="$(git config user.name)"
if [ -z "$GIT_NAME" ]; then
  echo "IDENTITY ERROR: git config user.name is empty. Set it as described in operators/ONBOARDING.md Step 4."
  exit 1
fi
MATCHES=""
for f in operators/*.md; do
  case "$f" in
    operators/CLAUDE.md|operators/ONBOARDING.md|operators/operator_template.md) continue ;;
  esac
  if awk '/^---$/{if(f)exit;f=1;next} f' "$f" | sed 's/^[[:space:]]*//' | grep -qxF -- "- $GIT_NAME"; then
    MATCHES="$MATCHES $f"
  fi
done
N=$(echo $MATCHES | wc -w | tr -d ' ')
if [ "$N" != "1" ]; then
  echo "IDENTITY ERROR: git user.name \"$GIT_NAME\" matches $N operator files:$MATCHES"
  echo "Exactly one operators/<slug>.md must claim this value in git_names."
  echo "Fix your identity or the registry (see operators/CLAUDE.md), then rerun."
  exit 1
fi
SLUG="$(basename $MATCHES .md)"
TODAY="$(date +%Y-%m-%d)"
echo "operator=$SLUG today=$TODAY"
```

On `IDENTITY ERROR`, stop the skill and show the message to the operator as it came
out. Do not continue with a guessed slug, and do not invent one from the git name.
The registry rule in `operators/CLAUDE.md` is binding:

> Resolve the active operator by matching `git config user.name` against every
> registry file's `git_names`. Exactly one match: proceed. Zero or multiple matches:
> stop and tell the user how to fix their identity or the registry. Never guess,
> never derive a slug from the name itself.

Zero matches on a fresh clone almost always means `SETUP.md` Step 3 (or
`operators/ONBOARDING.md` Step 4) has not been done on this machine yet. Fix it before
doing any work, not after: every commit made under an unregistered name is a commit no
skill can attribute.

---

## Step 1: Status snapshot

Start from where the working copy actually is.

```bash
cd "$(git rev-parse --show-toplevel)"
git status -sb
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "NO-REMOTE: this brain has no origin configured yet."
  exit 0
fi
```

Report three things to the operator from the `git status -sb` output: the current
branch, the ahead/behind counts against the tracking branch, and whether there are
uncommitted changes in the tree.

On `NO-REMOTE`, stop here. There is nothing to sync with: the brain is local-only
because `SETUP.md` has not been finished (Step 9, the first push, is what creates the
`origin` remote). Say that plainly and point at `SETUP.md` rather than trying to
continue.

If the branch is not `main`, say so and stop after Step 3's report. Rebasing a feature
branch onto a moved `origin/main` is a deliberate decision, not a hygiene routine, and
the branch is closed by `/ship` (see `docs/GOVERNANCE.md`). The integration block in
Step 4 refuses to run off `main` on purpose.

---

## Step 2: Skill-registration check (detect-only)

Claude Code discovers skills through a single container link, `.claude/skills`
pointing at this repo's `skills/` folder. The link is per-machine and gitignored, so a
fresh clone has the skills in git but not yet visible to Claude Code. The paths below are
relative, so the block starts by moving to the repo root: run from a subdirectory it
would look for `.claude/skills` in the wrong place, report a healthy setup as missing,
and then hand the operator a one-liner that creates a second, dangling link where it
does not belong.

```bash
cd "$(git rev-parse --show-toplevel)"
if [ -e ".claude/skills" ] || [ -L ".claude/skills" ]; then
  ls .claude/skills/ >/dev/null 2>&1 && echo "Skill registration: ok." \
    || echo "Skill link broken: recreate it (SETUP.md Step 4)."
else
  echo "Skills are not registered on this machine yet."
  echo "Run once: mkdir -p .claude && ln -s ../skills .claude/skills"
  echo "(Windows, from cmd in the repo folder: mklink /J .claude\\skills skills)"
fi
```

This checks that the container link resolves, and nothing more. It never creates the
link itself: the operator runs the one-liner, once per machine. Because the link points
at the whole folder rather than at each skill, there is no per-skill registration to
keep in step. New skills a teammate pushed are picked up automatically the moment they
land in `skills/`, which is why this check is a one-time setup detector rather than a
recurring drift report.

`Skill link broken` means `.claude/skills` is there but does not resolve, usually a
symlink left behind after the repo folder was moved or renamed. The fix is to delete it
first and then run the one-liner: `ln -s` refuses to overwrite an existing name, so
running the one-liner on top of a stale link fails with `File exists`. That is why the
test above checks for a symlink (`-L`) as well as for a resolving path (`-e`): a
dangling link has to reach the "broken" message, not the "not registered" one.

---

## Step 3: Fetch and report

```bash
git fetch origin --prune || { echo "FETCH FAILED: could not reach origin; not proceeding."; exit 2; }
git log HEAD..origin/main --oneline | head -20
```

`--prune` drops remote-tracking branches that no longer exist upstream, so the local
view of the remote does not accumulate branches that were merged and deleted months
ago.

If the log is empty, tell the operator "Already up to date with origin/main." If it is
not, list the incoming commits by subject. This is the useful part of a sync for a
human: not the count, but who did what while you were away. If more than 20 commits
came in, say so, since `head -20` truncated the list.

A network error here is reported once, as it came out, and the skill stops. No silent
retry, no second attempt with different flags: a fetch that failed is information about
the network, and hiding it makes the next step lie. The guard on the fetch is what makes
that promise real, and it is not decoration: without it a failed fetch leaves
`origin/main` pointing at whatever it knew hours or days ago, Step 4 computes
`ahead=0 behind=0` against that stale ref, and the skill cheerfully reports "already up
to date" to an operator who is a week behind. On `FETCH FAILED` (exit 2), tell the
operator the fetch failed and that nothing was compared, then stop.

---

## Step 4: Decide the action (divergence-aware)

Two counts decide everything that follows.

```bash
AHEAD=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
BEHIND=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
echo "ahead=$AHEAD behind=$BEHIND"
```

`AHEAD` is local commits origin has never seen. `BEHIND` is commits on origin this
copy has never seen. Four combinations, four different answers.

### Behind only (ahead=0, behind>0)

The normal case at the start of a session: teammates pushed, you have nothing local.
A fast-forward is enough, and `--ff-only` guarantees no merge commit can be invented.

If the tree is clean, run it directly:

```bash
git pull --ff-only origin main
```

If the tree is dirty, check first whether the incoming commits touch the same files as
the uncommitted edits. Pulling on top of your own edits to the same file is how context
gets lost:

```bash
DIRTY_LIST="${TMPDIR:-/tmp}/sync-dirty.$$"
INCOMING_LIST="${TMPDIR:-/tmp}/sync-incoming.$$"
git -c core.quotePath=false status --porcelain | grep -v "^??" | cut -c4- | sort -u > "$DIRTY_LIST"
git diff --name-only HEAD..origin/main | sort -u > "$INCOMING_LIST"
OVERLAP="$(comm -12 "$DIRTY_LIST" "$INCOMING_LIST")"
rm -f "$DIRTY_LIST" "$INCOMING_LIST"
if [ -n "$OVERLAP" ]; then
  echo "STOP: the incoming commits touch files you have uncommitted edits in:"
  echo "$OVERLAP"
  echo "Nothing was pulled and nothing was stashed. Decide in chat."
  exit 30
fi
git pull --ff-only origin main
```

On `STOP` (exit 30), show the overlapping paths and let the operator choose: commit
their edits first and rerun (which turns this into the divergent case below), or set
them aside deliberately. Never stash on their behalf. A stash is invisible in
`git status`, it may hold work from a session that is still open, and "I stashed it for
you" is how a day of work goes missing.

No overlap means the pull cannot disturb the uncommitted edits, so it proceeds.

### Ahead only (ahead>0, behind=0)

Local commits that never reached origin, typically a `DEFER` from an earlier debrief
that could not push. Show them and propose the push:

```bash
git log origin/main..HEAD --oneline
```

Then, with the operator's ok:

```bash
git push origin main
```

Nothing to integrate: origin has not moved, so this is a plain fast-forward on the
remote side.

### Ahead and behind (both >0): the histories diverged

Both sides moved. Before doing anything, check whether this is the expected kind of
divergence: after a debrief that ended in `PUSHED-VIA-WORKTREE`, local `main` still
points at the pre-rebase commits while origin already carries the same patches under
different hashes. That state is expected and benign. The rebase drops the duplicated
patches by itself and the copy realigns with no conflict. Verify by content, not by
hash: identical subjects with different SHAs in `git log origin/main..HEAD` and
`git log HEAD..origin/main` is the signature.

Either way the integration goes through the block below, which is the debrief engine's
integration half (the same block, minus its staging lines, because here the local
commits already exist). It re-checks its own preconditions, so it is safe to run even
if something changed between Step 4 and now: it refuses to run off `main`, refuses to
run on top of an unfinished merge or rebase, and picks its path from the state it finds.
A clean tree rebases in place. A dirty tree is integrated through a temporary worktree
instead, so a rebase never touches work in progress in the main tree.

**Ask the operator before running it.** This block does not only integrate: it also
pushes the local commits to the shared `main`, which is a write to everyone's brain and
not something a hygiene routine gets to decide on its own. Say what will happen, in one
sentence, naming the commits it will publish, and wait for the ok, exactly like the
ahead-only branch above. The only pre-authorized push in this brain is the one
`/session-debrief` makes at the end of its own run (see the carve-out in the root
`CLAUDE.md` rules); sync is not covered by it.

```bash
set -e
cd "$(git rev-parse --show-toplevel)"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "GUARD: HEAD is not on main"; exit 3; }
GD="$(git rev-parse --git-dir)"
if [ -e "$GD/MERGE_HEAD" ] || [ -d "$GD/rebase-merge" ] || [ -d "$GD/rebase-apply" ]; then
  echo "PRE-FLIGHT FAIL: a merge or rebase is already in progress; resolve it first"; exit 2
fi
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "LOCAL-ONLY: no origin remote configured; commit kept locally"; exit 0
fi
git fetch origin main --quiet
BEHIND="$(git rev-list --count HEAD..origin/main)"
if [ "$BEHIND" -gt 0 ]; then
  DIRTY="$(git -c core.quotePath=false status --porcelain | grep -v "^??" | cut -c4-)"
  if [ -n "$DIRTY" ]; then
    WTB="$(mktemp -d)"; WT="$WTB/wt"
    if ! git worktree add --detach --quiet "$WT" HEAD; then
      rm -rf "$WTB"; echo "DEFER: could not create a temporary worktree; push postponed, commit kept locally"; exit 10
    fi
    RES=10
    if git -C "$WT" rebase --quiet origin/main >/dev/null 2>&1; then
      if git -C "$WT" push origin HEAD:main; then
        RES=0; echo "PUSHED-VIA-WORKTREE: your work is on origin; the main tree was not touched and realigns on the next clean sync"
      else
        RES=40; echo "PUSH-RACE: origin advanced between fetch and push; commit safe locally, retry at the next debrief or /sync"
      fi
    else
      git -C "$WT" rebase --abort >/dev/null 2>&1 || true
      echo "DEFER: real conflict with origin; commit kept locally, resolve at the next clean sync"
    fi
    git worktree remove --force "$WT" >/dev/null 2>&1 || true
    git worktree prune >/dev/null 2>&1 || true
    rm -rf "$WTB"
    exit $RES
  fi
  if ! git pull --rebase origin main; then
    echo "CONFLICT: rebase stopped on a conflict; resolve in chat, inside the rebase"; exit 20
  fi
fi
git push origin main
echo "PUSHED"
```

On a clean tree this is exactly `git pull --rebase origin main` followed by the push of
whatever was local. On a dirty tree it is the worktree integration. Read the outcome
table before running it, so the result reaches the operator as a sentence rather than
as an exit code.

### Neither (ahead=0, behind=0)

Report it and stop: "In sync with origin/main." Also worth one line if the tree is
dirty, since uncommitted work is invisible to teammates until a debrief commits it.

### Outcomes

These exit codes are the only legitimate results of the integration block, plus the one
Step 3 can produce on its own. Anything else (a `1`, a `127`, a shell syntax error) is an
anomaly in how the block was run, not a result to look up here: stop, investigate the
command itself, and do not map it onto one of these rows.

| Exit | Marker | What to tell the operator |
|---|---|---|
| 0 | `PUSHED` | Aligned. The local commits are on origin and this copy matches `main`. |
| 0 | `PUSHED-VIA-WORKTREE` | The local commits are on origin and the working tree was never touched, so work in progress stayed intact. Local `main` still points at the pre-rebase commits and realigns by itself at the next clean pass, when the rebase drops the patches that are already upstream. Verify by content, not by hash. No action needed. |
| 10 | `DEFER` | Integration postponed: either a real conflict with what origin now holds, or a temporary worktree could not be created. Nothing was lost, the local commits are intact. Retry at the next clean moment, when the tree has no uncommitted work. |
| 40 | `PUSH-RACE` | Someone pushed in the seconds between the fetch and the push, so the push was refused. Nothing is lost and nothing gets forced. Rerun the sync. Two in a row is worth mentioning: it means sessions are closing on top of each other. |
| 20 | `CONFLICT` | The rebase is stopped on the conflict, not aborted, and it is waiting for a decision. Follow the conflict protocol below. First check `git status --porcelain` for unmerged (`UU`) paths. If there are none and `.git/rebase-merge` does not exist, no rebase ever started: this is an untracked-file collision (a local untracked file blocks an incoming file at the same path). The conflict protocol does not apply; decide in chat (typically move the local file aside with the operator's ok, then rerun). |
| 2 | `PRE-FLIGHT FAIL` | A merge or rebase was already in progress before this run, probably left stopped by an earlier session. Nothing was changed. Show it to the operator: an unfinished integration is a state to understand, not to push past. |
| 3 | `GUARD` | `HEAD` is not on `main`, so the block declined to run. Usually a feature branch (see Step 1). Check for a stopped rebase too (`git status`), because a rebase in progress leaves `HEAD` detached and trips this guard first. |
| 0 | `LOCAL-ONLY` | No `origin` remote. Step 1 normally catches this first; if it appears here, the remote was removed mid-run. Finish `SETUP.md`. |
| 2 | `FETCH FAILED` | From Step 3, not from the block: origin could not be reached, so nothing was fetched and nothing was compared. Report the git error as it came out and stop. Do not read the ahead/behind counts, and do not say "up to date": both would be measured against a stale `origin/main`. |

If a push fails on a network error, the local commits stay exactly where they are and
there is no silent retry.

### Conflict protocol (inside the rebase, never silent)

Exit 20 means the rebase is paused mid-flight with conflict markers in the tree. It is
not broken and nothing is lost; it is waiting for a human decision. Work through it
now, in this session. This is the same protocol as `session-debrief` Step 5, and the
two blocks below are byte-identical to the ones shipped there on purpose: there is one
way to close a conflicted rebase in this brain, not two.

1. Run `git status --porcelain` to list the conflicted files. Show the operator both
   sides in chat: yours is `git show REBASE_HEAD:<file>`, theirs is
   `git show HEAD:<file>` (during a rebase, `HEAD` is the origin/main side, which
   reads backwards until you have seen it once).
2. The resolution is the operator's explicit choice: mine, theirs, or both merged.
   Never resolve silently, and never pick for them. For a collision between two index
   lines in `memory/MEMORY.md`, the answer is almost always the union: both lines are
   true, keep both. The recipe is in `memory/CLAUDE.md` under "When two debriefs
   collide".
3. Apply the resolution with the Edit tool, removing the conflict markers, then close
   the rebase with a targeted `add`. Never `git add -A`, never `commit -a`, never
   `--amend`: each of those sweeps in files this session did not write.

```bash
set -e
git add <only-the-conflicted-files>
git update-index -q --ignore-submodules --refresh || true
if ! git diff-files --quiet; then
  echo "STOP: unstaged changes present in the tree; not forcing, not aborting. Decide in chat."; exit 30
fi
GIT_EDITOR=true git rebase --continue
git push origin main
```

   `git rebase --continue` refuses to run while any tracked file is unstaged, and
   `git rebase --abort` would hard-reset those edits out of existence. So when the
   guard prints `STOP` (exit 30), the correct move is neither: leave the rebase
   stopped, tell the operator which files are dirty, and decide in chat.

   If the continue reports that the commit became empty, because the resolution took
   "theirs" in full and the commit held nothing else, finish with
   `GIT_EDITOR=true git rebase --skip && git push origin main`.

4. If the continue stops on another conflict, repeat from step 1. Two retries at most,
   then take the safe abort below and report a `DEFER`.
5. If there is no immediate resolution (the operator has stepped away, the case is
   ambiguous), take the safe abort at once and report a `DEFER`. Never leave a rebase
   suspended past the end of the session: the next session's pre-flight will refuse to
   run, and the operator will not remember why.

### Safe abort

This is the only permitted way to abort a rebase in this skill. A bare
`git rebase --abort` does a hard reset that destroys **every** unstaged change in the
tree, including in-progress work that has nothing to do with the conflict. Guard
first. The guard deliberately excludes the unmerged conflict paths themselves, since
those are exactly what the abort is supposed to reset, and counts everything else:

```bash
set -e
git update-index -q --ignore-submodules --refresh || true
# git diff-files lists an unmerged path twice, once as U and once as M, so
# filtering on U alone would still leave the conflict looking dirty and the guard
# would refuse every abort. Tag the conflicted paths and drop them explicitly.
DIRTY="$( { git ls-files --unmerged | cut -f2 | sed 's/^/U /'
            git diff-files --name-only | sed 's/^/D /'; } \
          | awk '{p=substr($0,3)} $1=="U"{u[p]=1;next} !(p in u){print p}' | sort -u )"
if [ -n "$DIRTY" ]; then
  echo "STOP: aborting would destroy unstaged changes in:"; echo "$DIRTY"
  echo "Save that content first (explicit decision in chat), then rerun."; exit 30
fi
git rebase --abort
echo "DEFER: rebase aborted cleanly, local commit kept"; exit 10
```

On `STOP` (exit 30), the rebase stays exactly where it was: nothing was forced,
nothing was thrown away. Get the dirty content to safety first (whoever wrote it knows
what it is), then rerun the abort or the continuation.

An abort-on-conflict that skips this guard is the single most expensive mistake this
skill can make, which is why the plain form appears nowhere in it.

---

## Step 5: Confirm

```bash
git log -1 --format="%h %s" origin/main
git status -sb
```

Close with one line each: where `main` on the shared repo now is (hash and subject),
and where this copy stands. If the outcome was `DEFER`, `PUSH-RACE`, or a `STOP`, say
explicitly that nothing was lost and what happens next, so nobody goes hunting for
work that is sitting safely in a local commit.

---

## Rules

- **Never force-push.** Not to resolve a divergence, not to recover from
  `PUSH-RACE`, never. If a push is refused, that refusal is protecting a teammate's
  commit.
- **Never auto-resolve conflicts.** Report them, show both sides, let the operator
  choose.
- **Never abort a rebase without the guard.** A bare `git rebase --abort` throws away
  every unstaged change in the tree.
- **Never stash, checkout, or restore over uncommitted work.** If it is in the tree
  and you did not write it, leave it alone.
- **No silent retries.** A network error is reported once, as it came out.
- **Never invent a merge commit.** The behind-only path is `--ff-only`; the divergent
  path is a rebase. History stays linear.
- **Detect, do not repair, the skill link.** Step 2 reports; the operator runs the
  one-liner.

## Self-improvement

At the end of the run, check it against these friction triggers: **avoidable
round-trip · improvisation · breakage · token waste · operator correction**
(full definitions in `skills/_improvements/capture.md`). If at least one fired,
ask the operator "there was friction on X, should I log it?"; on their ok,
append an entry to `skills/_improvements/friction-log.md` in the format
`capture.md` defines. Clean run: say nothing. Never self-edit this skill;
improvements go through `/skill-improve`.
