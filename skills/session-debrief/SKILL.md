---
name: session-debrief
description: |
  End-of-session close: writes today's daily log, updates memory with approved
  changes, commits on main by allow-list, integrates with origin, pushes.
  Use when the operator says: debrief, /session-debrief, wrap up, close the
  session, close out the day, what do we save.
---

# Session debrief

This is how a session ends. It writes down what happened, updates what changed,
commits the result on `main`, integrates with whatever your teammates pushed while
you were working, and pushes. It is the only routine that moves the shared brain
forward, so it is deliberately conservative: it stages by allow-list, it asks before
writing to memory, and it stops rather than guessing whenever git gets interesting.

Run the steps in order. Do not skip Step 5 because the session felt small: an
uncommitted session is a session your teammates cannot see.

---

## Step 0: Resolve the operator

Everything downstream is keyed to the operator slug: the daily-log filename, the
`owner:` field on any memory file you create, and the debrief commit message. Resolve
it from the registry, never from the git name itself.

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

Zero matches usually means the operator has not been added to `operators/` yet, or
their `git config user.name` on this machine differs from the value the registry
claims (that value goes in the `git_names` list, which is a list precisely so a
second machine can add a second spelling). Two matches means two registry files claim
the same identity, which is a data problem to fix, not something to work around.

**Branch guard.** This skill is the daily flow, and the daily flow lives on `main`.
Check `git rev-parse --abbrev-ref HEAD`. If it does not print `main`, stop and ask the
operator what they want before touching anything. A feature branch is the opt-in flow
described in `docs/GOVERNANCE.md` section 2, and it is closed by `/ship`, not by a
push from here. If the operator confirms they are deliberately on a feature branch,
the debrief is commit-only: run Steps 1 through 4 as usual, then stage the same
allow-list and commit with the same message shape, and stop there. No fetch, no
rebase, no push to `main`. The engine block in Step 5 refuses to run off `main` on
purpose (exit 3).

---

## Step 1: Log the session

Read back over the conversation and write what happened into
`daily-log/${TODAY}-${SLUG}.md`, using the `TODAY` and `SLUG` values Step 0 printed.

If the file does not exist yet, create it with this skeleton, then fill it in:

```markdown
# YYYY-MM-DD - <slug>

## What happened

## Decisions

## Open threads
```

If it already exists (an earlier session today wrote it), read it first and append
your bullets under the existing sections rather than starting a second copy of them.

What goes under each section, per `daily-log/CLAUDE.md`:

- **What happened**: what was worked on, in plain terms. One bullet per concrete
  thing. A reader who was not in the session should understand what moved.
- **Decisions**: anything decided during the session, and why. The why is the part
  that stops the same debate from happening again in three weeks.
- **Open threads**: unfinished business to pick up next session. This is what the
  next daily briefing reads to rebuild context, so be specific: "waiting on the
  supplier quote before the pricing page can be finished", not "pricing pending".

Rules for the entry:

- Be concise but complete. No bullet quota: a small session gets two bullets, a long
  one gets twelve. Do not pad.
- Convert relative dates to absolute (`YYYY-MM-DD`) before writing them. "Next
  Thursday" is meaningless to whoever reads the log in March.
- Never edit another operator's log file. If this session touched their work, note it
  in your own log and let them pick it up in theirs.
- Do not backfill a past day's log with something learned later. It goes in today's.

**Write mechanism.** Use the Read tool before editing an existing file, and the
Edit or Write tools for the content itself. Never edit file content with `sed -i`,
`perl -pi`, `awk`, or shell heredocs: an apostrophe in ordinary prose (the company's
brief, the client's reply) terminates a single-quoted shell string and silently
corrupts or drops the write. This restriction is about file content only; the
`git add` / `git commit` / `git push` commands in this skill, and the `git mv` used
for archiving, are fine.

The log entry is auto-saved. It needs no approval, and it ships inside the debrief
commit in Step 5.

---

## Step 2: Draft memory changes (do not write yet)

**Hard rule: this step writes nothing.** Here you only identify and draft the
proposed changes, file by file, as old to new. Every write happens in Step 3, and
only after the operator has explicitly approved it. This is the root `CLAUDE.md`
rule "Memory changes are propose-then-write", and presenting a change you have
already applied is a violation of it, not a shortcut through it.

In the sub-steps below, "update", "create", and "archive" all mean *draft it for
Step 3*, not *do it now*.

### 2a: Status changes and the update trail

Read `memory/MEMORY.md`. For every project listed there, ask two questions:

1. **Did its status change?** Should the emoji move (🔴 urgent, 🟠 stalled or
   waiting, 🟡 active, 🟢 on track, 🔵 wrap-up, ❌ closed)? A status moves because a
   fact changed: a client signed, a deadline passed, a dependency unblocked. It never
   moves because the model felt it should. If the operator has not said something
   that implies the new status, do not draft the change.
2. **Did this session ship something into its scope?** If yes, the project file gets
   a line in `## Updates` even when the status is unchanged. `## Updates` is the
   trail of what actually happened; skipping it because the emoji did not move is the
   most common way a memory file quietly goes stale.

Both can be true at once. Draft the edits to the project file's `## Status`,
`## Next action`, and `## Updates` sections together with the matching change to its
index line in `MEMORY.md`.

**Index-line format** (from `memory/CLAUDE.md`), one line, no exceptions:

`- [Title](file.md) - <emoji> one line + Next action`

The line says three things and nothing more: what it is, what state it is in, what
happens next. Keep technical detail, tooling, prices, commit hashes, and deploy IDs
out of the index; that is what the project file is for. When you update a line,
**collapse** the previous state into the new one instead of appending to it, so the
index stays the same size after a hundred debriefs as it was after one. Absolute
dates only, never "today" or "last week".

Before adding anything, check whether an existing file already covers it and update
that one instead. Duplicated memory is worse than missing memory: two files disagree
and nobody knows which is current.

### 2b: New projects

Did this session start something that memory does not know about yet? Draft a new
file from `memory/project_template.md`, named `project_<slug>.md`, with frontmatter
per the shipped schema:

```yaml
---
name: project_<slug>       # matches the filename stem exactly
type: project
status: 🟡
deadline: YYYY-MM-DD       # optional; omit when there is no hard date
owner: <operator-slug>
---
```

Fill `## Status`, `## Next action`, `## Context`, and a first `## Updates` line.
Draft the index line for it too, under the right section of `MEMORY.md`.

Be conservative here. A new memory file is a commitment to keep it current; a
one-off task that finishes inside the session belongs in the daily log, not in
`memory/`.

### 2c: Strategic updates

Same pattern for `strategic_*` files: did this session reveal a shift in positioning,
a new long-term direction, or a change to a direction already recorded? Draft the
update, or a new file from `memory/strategic_template.md`, plus its index line.

Strategy shifts are rare. Most sessions draft nothing here, and that is the correct
outcome.

### 2d: Archive what closed

Closing an item means archiving it, never deleting it. The file is a historical
record and stays readable. Draft all four parts of the move together:

1. `status: ❌` in the frontmatter **and** in the `## Status` body line. A mismatch
   between the two is the classic half-archived file.
2. A closing entry in `## Updates`: the date, that it closed, and why.
3. The file moves with `git mv memory/project_<slug>.md memory/archive/`.
4. Its index line moves from its section down to `## Archive` in `MEMORY.md`,
   rewritten as closed, with a pointer to wherever the thread continues (a
   `[[wikilink]]` to the project that superseded it, when there is one).

The target state is simple: every file in `memory/archive/` is listed exactly once
under `## Archive`, and reads as closed from both its frontmatter and its body.

### Advanced layer, if adopted

If this team has adopted `docs/ADVANCED.md`, the project files carry two extra
frontmatter fields, `last_touched` and `salience`. For the files this session
touched, and only those, draft `last_touched: <today>` and a recomputed `salience`
using the deterministic formula in `docs/ADVANCED.md` (never an eyeballed number,
never a judgment call). Show the delta in the Step 3 list, for example
`project_website 0.9 to 0.8`, so the operator approves it like any other change.
Files this session did not touch are rebalanced by the advanced layer's own sweep,
not here. If the fields are not present in the frontmatter, the team has not adopted
the layer: skip this silently and say nothing about it.

---

## Step 3: Present and approve

Show the operator everything drafted in Step 2 as a numbered list, one line per item,
in the shape "file, what changes, from what to what". If the session also produced a
structural change that belongs in a `CLAUDE.md` (a new area folder, a changed
convention, a new skill), propose that edit here too, as its own numbered item with a
recommendation attached: propose, with a one-line why, or skip, with why it is not
needed. The default for a borderline `CLAUDE.md` edit is skip. `CLAUDE.md` files
decide how every agent in the system behaves and are never edited without their own
explicit approval.

Then ask exactly one question, for the whole batch:

> Approve these updates?

Wait for the reply. Write nothing until it arrives. The operator may approve
everything, approve some items, reject, or skip the lot.

This is the first and only point where the Step 2 drafts reach disk. Apply only the
approved items, reading each file with the Read tool first and editing it with Edit
or Write (same write mechanism as Step 1). Confirm each write in one short line as
you go.

If Step 2 drafted nothing, say so plainly: "No memory changes this session." That is
an honest and frequent outcome. Do not manufacture an update to make the debrief feel
productive.

---

## Step 4: Detect content work outside `daily-log/` and `memory/`

The debrief commit carries only `daily-log/` and `memory/`. Everything else this
session produced (work under `areas/`, a doc at the root, a new skill file) stays
uncommitted in the working tree unless this step catches it, and uncommitted work is
work your teammates never receive.

```bash
git -c core.quotePath=false status --short --untracked-files=all
```

`--untracked-files=all` matters: without it a brand new folder collapses to a single
`?? areas/` line, which tells you nothing about what is inside and makes a targeted
`git add` impossible. With it, every new file is listed individually.

Ignore the lines under `daily-log/` and `memory/`: those belong to Step 5. Group
everything else by area, where "same folder" means "same group": one group per
`areas/<name>/` topic, one group for a skill directory, one for root-level docs.

Propose one commit per group, each with a subject, and ask **once** for the whole
batch (`Y / n / edit`). Do not ask group by group. On `Y`, commit the groups in the
order shown, before the debrief commit:

```bash
git add <paths-of-this-group>
git commit -m "<area>: <what this group is>"
```

On `n`, skip them: the debrief commit will carry only the log and memory. On `edit`,
ask which groups to split, merge, or rename, then commit the revised set.

Skip a group on your own initiative only when its diff is visibly half-written (a
truncated file, a script that does not parse, a stray temp file). When in doubt, ask.
Never end a session reporting "done" while this session's content work is still
sitting uncommitted in the tree.

---

## Step 5: Commit, integrate, push (the engine)

Staging is **allow-list only**. Never `git add .`, never `git add -A`, never
`git add daily-log/ memory/` wholesale. The allow-list is the explicit list of files
this session wrote in Step 1 and Step 3: today's daily log, plus each memory file
that was approved and changed, plus `memory/MEMORY.md` when its index changed. If
Step 2d archived something, that file contributes **two** paths to the allow-list, its
old location and its new one under `memory/archive/`, because a `git mv` is recorded as
a deletion plus an addition. Write the list out before you run anything.

**Substitute three placeholders as literal text, not as shell variables.** Replace
`<allow-list-for-this-session>` with the paths, and replace `$TODAY` and `$SLUG` with
the actual values Step 0 printed (for example `debrief: 2026-03-14 1830 (jane-doe)`).
Step 0 and Step 5 are separate shell invocations, so nothing set in Step 0 still
exists here: left as variables they expand to nothing and the commit subject ships as
`debrief:  1830 ()`. The alternative, if you would rather not hand-substitute, is to
paste Step 0's block and this block into the **same** invocation so the assignments
are still live.

**Check the index before staging.** `git add <allow-list>` adds to whatever is already
staged, and the `git commit` that follows commits the entire index, not just your
allow-list. So anything a previous step or an earlier session left staged rides along
into the debrief commit and gets pushed, which would quietly break the promise that
this commit carries only `daily-log/` and `memory/`:

```bash
git diff --cached --name-only
```

If that prints nothing, or only paths on your allow-list, continue. If it prints
anything else (typically a file under `areas/` that the operator declined to commit in
Step 4), stop and show it to the operator. Unstage it only with their explicit ok:

```bash
git restore --staged <path>
```

`git restore --staged` moves the file out of the index and leaves its content on disk
untouched, so nothing is lost. Never unstage silently, and never proceed with foreign
content staged.

The block commits, then decides how to integrate with `origin/main` based on two
facts: whether origin has moved ahead of you, and whether your working tree is
dirty. A clean tree rebases in place. A dirty tree is integrated through a temporary
worktree instead, so that in-progress edits in the main tree are never touched by a
rebase. Read the outcome table below before running it, so you can explain the result
to the operator in the words they need rather than an exit code.

```bash
set -e
cd "$(git rev-parse --show-toplevel)"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "GUARD: HEAD is not on main"; exit 3; }
GD="$(git rev-parse --git-dir)"
if [ -e "$GD/MERGE_HEAD" ] || [ -d "$GD/rebase-merge" ] || [ -d "$GD/rebase-apply" ]; then
  echo "PRE-FLIGHT FAIL: a merge or rebase is already in progress; resolve it first"; exit 2
fi
git add <allow-list-for-this-session>
git commit -m "debrief: $TODAY $(date +%H%M) ($SLUG)"
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

### Outcomes

These exit codes are the only legitimate results of the block. Anything else (a
`1`, a `127`, a shell syntax error) is an anomaly in how the block was run, not a
result to look up in this table: stop, investigate the command itself, and do not
map it onto one of these rows.

| Exit | Marker | What to tell the operator |
|---|---|---|
| 0 | `PUSHED` | Done. The session is committed and `main` on the shared repo now has it. |
| 0 | `LOCAL-ONLY` | There is no remote yet, so the commit is on this machine only. Normal before the first push of a fresh brain; finish `SETUP.md` to add the remote. |
| 0 | `PUSHED-VIA-WORKTREE` | The work is on origin and the working tree was never touched, so work in progress stayed intact. Local `main` still points at the pre-rebase commits and realigns by itself at the next clean `/sync` or debrief, when the rebase drops the patches that are already upstream. Verify by content, not by commit hash: the hashes differ by design. No action needed. |
| 10 | `DEFER` | The commit is safe locally, the push is postponed: either a real conflict with what origin now holds, or a temporary worktree could not be created. Note it in the log and retry at the next clean moment. |
| 40 | `PUSH-RACE` | Someone else pushed in the seconds between the fetch and the push, so the push was refused. Nothing is lost and nothing gets forced; retry at the next debrief or `/sync`. Two of these in a row is worth mentioning to the operator: it means sessions are closing on top of each other. |
| 20 | `CONFLICT` | The rebase is stopped on the conflict, not aborted, and it is waiting for a decision. Follow the conflict protocol below. First check `git status --porcelain` for unmerged (`UU`) paths. If there are none and `.git/rebase-merge` does not exist, no rebase ever started: this is an untracked-file collision (a local untracked file blocks an incoming file at the same path). The conflict protocol does not apply; decide in chat (typically move the local file aside with the operator's ok, then rerun). |
| 2 | `PRE-FLIGHT FAIL` | A merge or rebase was already in progress before this run. Nothing was committed. Show it to the operator and stop: an unfinished integration is a state to understand, not to push past. |
| 3 | `GUARD` | `HEAD` is not on `main`. Nothing was committed. Usually a feature branch: go back to the branch guard in Step 0. Check for a stopped rebase too (`git status`), because a rebase in progress leaves `HEAD` detached, which trips this guard before the pre-flight check below can report it. |

If a push fails on a network error, the commit stays, the log records it, and there
is no silent retry.

### Conflict protocol (inside the rebase, never silent)

Exit 20 means the rebase is paused mid-flight with conflict markers in the tree. It
is not broken and nothing is lost; it is waiting for a human decision. Work through
it now, in this session.

1. Run `git status --porcelain` to list the conflicted files. Show the operator both
   sides in chat: yours is `git show REBASE_HEAD:<file>`, theirs is
   `git show HEAD:<file>` (during a rebase, `HEAD` is the origin/main side, which
   reads backwards until you have seen it once).
2. The resolution is the operator's explicit choice: mine, theirs, or both merged.
   Never resolve silently, and never pick for them. For a collision between two
   index lines in `memory/MEMORY.md`, the answer is almost always the union: both
   lines are true, keep both. The recipe is in `memory/CLAUDE.md` under "When two
   debriefs collide". Read closely only when both sides changed the *same* item's
   line, which is a real disagreement about one project's status.
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

4. If the continue stops on another conflict, repeat from step 1. Two retries at
   most, then take the safe abort below and report a `DEFER`.
5. If there is no immediate resolution (the operator has stepped away, the case is
   ambiguous), take the safe abort at once and report a `DEFER`. Never leave a rebase
   suspended past the end of the session: the next session's pre-flight will refuse
   to run, and the operator will not remember why.

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
nothing was thrown away. Get the dirty content to safety first (whoever wrote it
knows what it is), then rerun the abort or the continuation.

---

## Step 6: Confirm

Close with one short message covering four things, in plain language:

- the daily-log file that was written, by name;
- the memory items updated, or "no memory changes this session";
- any content commits from Step 4, listed by subject;
- the engine outcome, explained rather than named: "committed and pushed, `main` is
  shared" beats "exit 0".

If the outcome was `DEFER` or `PUSH-RACE`, say explicitly that the work is safe
locally and what will happen next, so nobody goes hunting for a lost session.

---

## Rules

- **Allow-list staging only.** Never `git add .`, `git add -A`, or a blanket add of
  `daily-log/` and `memory/`.
- **Never force-push.** Not to recover from `PUSH-RACE`, not to tidy history, never.
- **Never skip hooks** (`--no-verify`).
- **Never resolve a conflict silently.** The operator chooses; you apply.
- **Never abort onto a dirty tree.** Use the safe abort, and respect its `STOP`.
- **Never stash, checkout, or restore over uncommitted work.** If it is in the tree
  and you did not write it, leave it alone.
- **Memory writes happen only after approval.** Step 2 drafts, Step 3 writes.
- **Be honest.** Plenty of sessions change no project status. Say so; do not invent
  movement to fill the report.
- **Keep memory lean.** Update the file that exists instead of adding a near
  duplicate.
- **Convert relative dates to absolute** everywhere something gets saved.
- **Never leave a rebase suspended past the session.** Resolve it inside the rebase
  or abort safely and defer.

## Self-improvement

At the end of the run, check it against these friction triggers: **avoidable
round-trip · improvisation · breakage · token waste · operator correction**
(full definitions in `skills/_improvements/capture.md`). If at least one fired,
ask the operator "there was friction on X, should I log it?"; on their ok,
append an entry to `skills/_improvements/friction-log.md` in the format
`capture.md` defines. Clean run: say nothing. Never self-edit this skill;
improvements go through `/skill-improve`.
