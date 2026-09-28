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
the branch is closed by `/ship` (see `docs/GOVERNANCE.md`). The engine Step 4 delegates
to refuses to run off `main` on purpose (exit 3).

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
git fetch origin --prune || { echo "FETCH FAILED: could not reach origin; not proceeding."; exit 50; }
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
to date" to an operator who is a week behind. On `FETCH FAILED` (exit 50), tell the
operator the fetch failed and that nothing was compared, then stop. The code is the
engine's own for the same marker (`skills/session-debrief/reference/push-outcomes.md`,
exit 50): one marker, one code, so an agent that looks it up cannot land on the row of
a different situation.

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
cd "$(git rev-parse --show-toplevel)"
scripts/git-locked git pull --ff-only origin main
```

If the tree is dirty, check first whether the incoming commits touch the same files as
the uncommitted edits. Pulling on top of your own edits to the same file is how context
gets lost:

```bash
cd "$(git rev-parse --show-toplevel)"
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
scripts/git-locked git pull --ff-only origin main
```

On `STOP` (exit 30), show the overlapping paths and let the operator choose: commit
their edits first and rerun (which turns this into the divergent case below), or set
them aside deliberately. Never stash on their behalf. A stash is invisible in
`git status`, it may hold work from a session that is still open, and "I stashed it for
you" is how a day of work goes missing.

No overlap means the pull cannot disturb the uncommitted edits, so it proceeds.

### Ahead only (ahead>0, behind=0)

Local commits that never reached origin, typically a `DEFER` or a `PUSH-RACE` from an
earlier debrief. Show them and propose the push:

```bash
git log origin/main..HEAD --oneline
```

Then, with the operator's ok, push them through the engine's integrate-only mode,
which pushes and verifies by content that every line they added or removed is
reflected on `origin/main`:

```bash
cd "$(git rev-parse --show-toplevel)"
scripts/git-locked scripts/debrief-push.sh --integrate-only
```

Nothing to integrate: origin has not moved, so this is a plain fast-forward on the
remote side, and the expected outcome is exit 0 with `PUSHED`. Any other exit is read
exactly as in the divergent case below: exit 75 is the lock held by another live
session, and everything else is looked up in
`skills/session-debrief/reference/push-outcomes.md`.

### Ahead and behind (both >0): the histories diverged

Both sides moved. This is one of two very different situations, and the difference is
invisible in the counts:

1. **After a debrief that ended in `PUSHED-VIA-WORKTREE`.** Local `main` still points
   at the pre-rebase commits; origin carries the same work under different hashes.
   Their content is on origin. Rebasing them is the wrong move: the replayed patches
   are not identical (the rebase in the worktree changed their context), so git does
   not drop them as duplicates, it replays them as spurious conflicts, and "keep mine"
   there regresses what others wrote.
2. **Local commits that never reached origin** (a `DEFER`, a `PUSH-RACE`, a network
   failure). Their content is not on origin. They must be integrated.

Decide by content, never by hash or subject. The verifier answers exactly this
question for every line a commit added or removed, and it also writes a
remote-tracking ref (it fetches origin internally), so it goes through the lock like
every other git call here.

Ask it one commit at a time, not once for the whole fork-point range. The commit is
the unit a rebase drops or replays, so it is the unit the answer has to hold for; and
the verifier's refusal to confirm what it cannot read by content (a binary file, a
mode-only change, a blank line, a removed line that repeats in its file) then falls on
that commit alone, instead of being satisfied by a checkable neighbour in the same
range. The loop runs inside one lock, so every commit is compared against the same
state of origin, and it names the commits rather than just counting them:

```bash
cd "$(git rev-parse --show-toplevel)"
scripts/git-locked bash -c '
  UNVERIFIED=""
  for c in $(git rev-list --reverse "$(git merge-base HEAD origin/main)"..HEAD); do
    echo "=== $(git log -1 --format="%h %s" "$c")"
    scripts/debrief-verify.sh "$c^" "$c" - || UNVERIFIED="$UNVERIFIED $c"
  done
  [ -z "$UNVERIFIED" ] && echo "ALL VERIFIED: every local commit is reflected on origin/main" \
                       || echo "NOT ALL VERIFIED:$UNVERIFIED"
'
```

**`ALL VERIFIED`** (every commit reported `VERIFY OK`): case 1. Each local commit's
content is already on origin, so nothing is lost by moving off them. Propose the
realignment and run it with the operator's ok:

```bash
cd "$(git rev-parse --show-toplevel)"
scripts/git-locked git reset --keep origin/main
```

`--keep` preserves uncommitted work on files the move does not touch, and refuses
(changing nothing) when it would touch one; on a refusal, follow "Realign refused" in
`skills/session-debrief/reference/push-outcomes.md`. Never rebase here.

**`NOT ALL VERIFIED`** (one commit short of the whole range is enough to land here):
case 2, or a mix. The commits it names
carry work origin does not have, or work this check could not read either way; neither
is something to discard, and `reset --keep` would discard both alike. Integrate instead,
through the engine in integrate-only mode, which rebases in place on a clean tree or
through a temporary worktree on a dirty one, pushes, and verifies again:

```bash
cd "$(git rev-parse --show-toplevel)"
scripts/git-locked scripts/debrief-push.sh --integrate-only
```

**Ask the operator before running it.** It pushes to the shared `main`, which is a
write to everyone's brain and not something a hygiene routine decides on its own. Say
what will be published, naming the commits (`git log origin/main..HEAD --oneline`),
and wait for the ok. The only pre-authorized push in this brain is the one
`/session-debrief` makes at the end of its own run (see the carve-out in the root
`CLAUDE.md` rules); sync is not covered by it.

The outcome of `--integrate-only` is read exactly like the debrief's: exit 0 with
`PUSHED` or `PUSHED-VIA-WORKTREE` is done (with the same `LOCAL-MAIN-DIVERGED`
follow-up when printed); exit 75 is the lock held by another live session (retry on a
later tool turn); any other exit is looked up in
`skills/session-debrief/reference/push-outcomes.md`, whose path the script prints.
Exit 20 and 21 (a stopped rebase, in the main tree or in the temporary worktree) are
resolved inside the rebase, following that reference: show both sides, the operator
chooses, never silent, never `--skip` as the fallback of a failed `--continue`, never
a bare `rebase --abort` on the main tree.

### Neither (ahead=0, behind=0)

Report it and stop: "In sync with origin/main." Also worth one line if the tree is
dirty, since uncommitted work is invisible to teammates until a debrief commits it.

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
  choose. The engine's `autoTake` team option is the one declared exception, off by
  default and declared in its output whenever it fires.
- **Never abort a rebase without the guard.** A bare `git rebase --abort` throws away
  every unstaged change in the tree. The guarded form lives in
  `skills/session-debrief/reference/push-outcomes.md` (exit 20).
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
