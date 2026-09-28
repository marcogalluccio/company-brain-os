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
IN_WORKTREE=$([ "$(git rev-parse --path-format=absolute --git-dir 2>/dev/null || echo unknown-git-dir)" = "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo unknown-common-dir)" ] && echo no || echo yes)
echo "operator=$SLUG today=$TODAY branch=$(git rev-parse --abbrev-ref HEAD) linked-worktree=$IN_WORKTREE"
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

**Branch guard.** This skill is the daily flow, and the daily flow lives on `main`,
together with the two kinds of file every session writes: the daily log and memory
(every root's memory, index files included). Those are shared files, written by
every session and read by every teammate, so they are committed on `main` and
nowhere else. Read `branch=` and `linked-worktree=` from the line Step 0 printed:

- **`main`, `linked-worktree=no`**: the normal flow. Continue with Step 1.
- **A feature branch, `linked-worktree=yes`**: the session worked on a feature branch
  in its own worktree (`docs/GOVERNANCE.md` step 2). Never write or commit the daily
  log or memory inside that worktree: a copy committed on the branch forks a file
  that other sessions keep writing on `main`, teammates read stale memory until the
  merge, and at merge time the fork conflicts with what they wrote meanwhile, where a
  "keep mine" resolution regresses their content. Instead:
  1. Commit only the branch's own work, in the worktree: one targeted add per file
     this session changed there, nothing under `daily-log/` or `memory/` (or
     `areas/<name>/memory/`), no fetch, no push. `/ship` opens the pull request
     later. With the paths substituted as literal text:

     ```bash
     git add -- "areas/tools/check.sh" "docs/GOVERNANCE.md"
     git commit -m "<area>: <what this work is>"
     ```

     If the worktree already holds uncommitted edits under those shared folders,
     leave them out of this commit and name them to the operator: Step 2 redrafts
     their content from the main tree, where it passes the gate like any other
     memory change.
  2. Propose leaving the worktree for the main tree, and wait for the ok. The main
     tree is the first line of `git worktree list`.
  3. From the main tree, on `main`, rerun Step 0 and continue with Steps 1 through 5
     exactly as in the normal flow. The log entry names the branch and what was
     committed on it.
- **Anything else** (the main tree on a branch other than `main`, a detached
  `HEAD`): an anomalous state. Stop and ask the operator before touching anything.
  The engine in Step 5 refuses to run off `main` on purpose (exit 3).

The branch commit in the feature-branch case runs under `scripts/git-locked` when
the harness allows it; a session isolated in its own worktree may have to run it bare
(the documented exception in `reference/push-outcomes.md`, "The lock"): the branch is
yours alone, so contention is nil.

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
- The entry never forecasts the commit. Whether a file enters the debrief commit is
  decided in Steps 4 and 5, on a fresh view of the tree, and can change while the
  debrief runs (a parallel session may commit in the meantime). If the tree holds
  work this session did not do, the entry says "left untouched" and nothing more.

**Write mechanism.** Use the Read tool before editing an existing file, and the
Edit or Write tools for the content itself. Never edit file content with `sed -i`,
`perl -pi`, `awk`, or shell heredocs: an apostrophe in ordinary prose (the company's
brief, the client's reply) terminates a single-quoted shell string and silently
corrupts or drops the write. This restriction is about file content only; the
`git add` / `git commit` / `git push` commands in this skill, and the `git mv` used
for archiving, are fine.

A line too long for the Read tool comes back truncated, and Edit cannot match text
it never saw. Read that one line alone (`offset` set to its line number, `limit` 1),
then Edit with `old_string` set to a short prefix of the line that is unique in the
file, never the whole line; then bring the line back within budget (Step 2a).

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

Read `memory/MEMORY.md`. If it has a `## Areas` section, the team runs federated
memory roots (`docs/ADVANCED.md` section 8): also read the `MEMORY.md` of every area
root the session touched, following those pointer rows. An item has one home, the
root that owns its next action; its file and its index row live in that same root,
never in both (the gate reports `DUP-ROOT`). For every project listed, ask two
questions:

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

The same rule holds inside the project file. `## Status` and `## Next action` are
rewritten in the present tense at every debrief, never appended to; the chronology
of what happened belongs in `## Updates`. A Status or Next action longer than an
index line is already out of standard: move the detail into `## Updates` or into a
note in the project's own folder, link it, and keep the line to what it is, where it
stands, and what comes next.

Before adding anything, check whether an existing file already covers it and update
that one instead. Duplicated memory is worse than missing memory: two files disagree
and nobody knows which is current.

**Measure before you write (read-only, one command).** The "collapse, don't append"
rule above only holds if something measures it. Before drafting any index line, run:

```bash
cd "$(git rev-parse --show-toplevel)"
if command -v python3 >/dev/null 2>&1 && [ -f scripts/memory_gate.py ]; then
  python3 scripts/memory_gate.py --only BUDGET,ROW-BUDGET | python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join(f["detail"] for f in d["findings"]) or "index within budget")'
else
  echo "index budget not measured (python3 or scripts/memory_gate.py not available)"
fi
```

It writes nothing and touches no generated file, so it is safe with other sessions
open on the same clone. Read two things and act on them:

- A `BUDGET` line means `MEMORY.md` is past 90% of its auto-load cap: do not add a row
  in this debrief without collapsing at least one.
- A `ROW-BUDGET` line names the heaviest rows. **If a row you are about to touch is
  among them, collapse it now**: this is the one moment you hold the context to do it
  without losing anything. If it is not, leave it; this is not an invitation to prune
  the whole index.

The per-row budget is derived from the file (`scripts/memory_gate.py`, `row_budget`).
Do not raise it to silence the check.

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
Draft the index line for it too, under the right section of the `MEMORY.md` of the
root where the file lives (`memory/`, or `areas/<name>/memory/` when that area has its
own root and owns the next action). Exception: a
new `type: reference` file gets its row in `memory/REFERENCES.md`, not in `MEMORY.md`
(same row format); the index is auto-loaded every session and has a size cap, so it
carries only what the briefing builds priorities from.

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
3. The file moves with `git mv` into the `archive/` folder of its own root
   (`memory/archive/`, or `areas/<name>/memory/archive/`).
4. Its index line moves out of its root's `MEMORY.md` into that root's `archive/INDEX.md`, rewritten
   as closed, with a link relative to the archive folder and a pointer to wherever the
   thread continues: `- [Title](project_<slug>.md) - ❌ YYYY-MM-DD, why, superseded by
   [[project_other]]` (the wikilink only when there is a successor). `MEMORY.md` keeps
   no per-item row for closed work: it has a size cap, and a closed item spends that
   budget every session for nothing.

The target state is simple: every file in a root's `archive/` is listed exactly once
in that root's `archive/INDEX.md`, and reads as closed from both its frontmatter and
its body.

### Advanced layer, if adopted

If this team has adopted `docs/ADVANCED.md`, the project files carry two extra
frontmatter fields, `last_touched` and `salience`. For the files this session
touched, and only those, draft `last_touched: <today>` and a recomputed `salience`
using the deterministic formula in `docs/ADVANCED.md` (never an eyeballed number,
never a judgment call). When `python3 scripts/salience_sweep.py` is available, read
the `computed` value for each touched file from its `scores` output after setting
`last_touched` in your draft to today; otherwise work the formula by hand. Show the
delta in the Step 3 list, for example
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

Every `CLAUDE.md` item also carries its route, in the same line. Run the classifier
on the path, with the slug Step 0 printed (`scripts/classify-paths.sh --operator
<slug-from-step-0> <path>`): `structural` means the file is one of the protected
system files the team listed in `.github/structural-paths.txt`, and an approval
sends it to a feature branch through Step 4's split, never into the debrief commit;
`normal` means an area `CLAUDE.md`, which lands on `main` with the debrief after
approval, as before (`docs/GOVERNANCE.md` step 2 explains the two tiers). A
`sensitive` or `carve-out` result is handled exactly the way Step 4 handles it, so no
class falls through here either. On a template where the list is still inert, every
`CLAUDE.md` is `normal`.

Then ask exactly one question, for the whole batch:

> Approve these updates? A bare "ok" approves every item as listed, each on the
> route its line already shows: `normal` items land on `main` with the debrief,
> `structural` ones go to the Step 4 split.

Wait for the reply. Write nothing until it arrives. The operator may approve
everything, approve some items, reject, or skip the lot. A bare "ok" is the
explicit default, not an ambiguity to resolve with a second question: apply it as
stated.

This is the first and only point where the Step 2 drafts reach disk. Apply only the
approved items, reading each file with the Read tool first and editing it with Edit
or Write (same write mechanism as Step 1). Confirm each write in one short line as
you go.

If Step 2 drafted nothing, say so plainly: "No memory changes this session." That is
an honest and frequent outcome. Do not manufacture an update to make the debrief feel
productive.

---

## Step 4: Detect content work outside `daily-log/` and `memory/`

The debrief commit carries only `daily-log/`, `memory/`, and, for a team with federated roots, `areas/<name>/memory/`. Everything else this
session produced (work under `areas/`, a doc at the root, a new skill file) stays
uncommitted in the working tree unless this step catches it, and uncommitted work is
work your teammates never receive.

```bash
git -c core.quotePath=false status --short --untracked-files=all
```

`--untracked-files=all` matters: without it a brand new folder collapses to a single
`?? areas/` line, which tells you nothing about what is inside and makes a targeted
`git add` impossible. With it, every new file is listed individually.

### Whose change is this? (provenance, before classifying)

Several sessions can share one working tree, so not every line `git status`
prints is this session's. Classify every path, using the Step 1 entries as the
record of what this conversation actually did:

- **This session's work**: paths this conversation created or edited. They go on
  to the classifier and the groups below.
- **Foreign work**: a separate file on a topic this conversation never touched
  (a project file you did not write, a new folder you did not create, a topic
  absent from this chat). Leave it strictly untouched: no stage, no commit, no
  revert, no clean-up. One `## Open threads` bullet in your log ("the tree held
  another session's work on X, left untouched") and nothing more.
- **Both in one file**: a shared file this session and another one both edited.
  That is a co-write, handled by file type in Step 5, never a reason to strip
  the other session's lines. A path with both kinds of hunks is a co-write, not
  this session's work.

Foreign paths are never offered a split and never enter a group.

**Classify before you group.** Every path the status printed, including the ones under
`daily-log/`, `memory/`, and `areas/<name>/memory/`, goes through the classifier first, with the slug Step 0
printed substituted as literal text:

```bash
cd "$(git rev-parse --show-toplevel)"
PATHS="$(git -c core.quotePath=false status --short --untracked-files=all \
  | cut -c4- | sed 's/^.* -> //' | sed 's/^"//; s/"$//')"
[ -n "$PATHS" ] && printf '%s\n' "$PATHS" | tr '\n' '\0' \
  | xargs -0 scripts/classify-paths.sh --operator <slug-from-step-0>
```

The quote stripping runs after the rename arrow is removed, because a renamed path
arrives as `"old name.md" -> "new name.md"` and the arrow stage has to go first. It
covers the ordinary case of a space in a name; a file whose name contains a literal
double quote or a newline is not classified reliably by this pipeline and should be
renamed.

One line per path, `<class>` then the path. `normal` and `carve-out` continue into the
grouping below. `structural` and `sensitive` do not: they never enter a Step 4 group
and never reach the Step 5 allow-list, because the debrief commits on `main` and those
paths are not allowed there (`docs/GOVERNANCE.md` steps 2 and 3). Read the decision
from the class printed on each line, not from the block's exit status: the classifier
runs under `xargs`, which does not pass its own exit `4` through unchanged.

For each `structural` or `sensitive` path that the operator approved, offer the split
and open `skills/session-debrief/reference/split-paths.md` for the procedure: a feature
branch in a worktree for `structural` (every operator), a proposal pull request for
`sensitive` (an operator who is not a sensitive owner; owners never see this class).
If the operator declines the split for now, the file stays uncommitted in the tree and
today's daily log gets a `Pending:` line naming it, so the next debrief finds it again.
Never commit a listed path on `main` "just this once".

If the classifier printed a `warning:` about an unknown operator, stop: Step 0's slug
and the registry disagree, and that is a data problem to fix before pushing anything.

Ignore the remaining lines under `daily-log/`, `memory/`, and `areas/<name>/memory/`: those belong to Step 5.
Group everything else by area, where "same folder" means "same group": one group per
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

The one exception is a listed path whose split the operator declined: that one is
reported as `Pending:`, by name, in the daily log and in the closing message.

---

## Step 5: Commit, integrate, push (the engine)

Staging is **allow-list only**. Never `git add .`, never `git add -A`, never a
directory: the engine refuses a directory argument on purpose (exit 64), because a
blanket add sweeps in work this session did not write. The allow-list is the explicit
list of files this session wrote in Step 1 and Step 3: today's daily log, plus each
memory file that was approved and changed (under `memory/` or under an area root
`areas/<name>/memory/`), plus each `MEMORY.md` whose index changed, plus
`memory/REFERENCES.md` when a reference row was added. If Step 2d
archived something, that item contributes **three** paths to the allow-list: the
file's old location, its new one under its own root's `archive/` (`memory/archive/`,
or `areas/<name>/memory/archive/`; a `git mv` is recorded as a deletion plus an
addition), and that root's `archive/INDEX.md`, which received the row.
Write the list out before you run anything.

Every path on the allow-list must have come out of the Step 4 classifier as `normal`
or `carve-out`: `memory/CLAUDE.md` in particular is a protected file once
`docs/GOVERNANCE.md` step 2 is adopted, and travels through the split, not through
this commit.

**Shared files.** When a file on the allow-list also carries another session's
uncommitted hunks, the rule depends on the file, because the files differ in what
a combined commit means:

- **Your per-operator daily log** (`daily-log/<date>-<slug>.md`): always commit
  it combined. It is append-only and its entries pass through no gate, so two
  entries on different topics are the file working as designed, not a conflict.
- **Every index file on the allow-list** (`MEMORY.md` of any root,
  `memory/REFERENCES.md`, a root's `archive/INDEX.md`): commit it combined when
  the foreign hunks are lines you did not touch (added or changed elsewhere in the
  file), since every index line has already passed its own debrief's gate. If a
  foreign hunk removes a line without replacing it, keep the file off the
  allow-list and note it as an open thread.
- **Any other file** (a project file, a content file): keep it off the allow-list
  and note it as an open thread. Your change is safe on disk; the next debrief
  or the other session's commit carries it. Never strip the other session's
  lines, never `git add -p`.

**Compose the list right before the engine runs**, from a fresh
`git -c core.quotePath=false status --short --untracked-files=all`, and run the Step 4 classifier on
any path that was not in Step 4's output; only `normal` and `carve-out` paths
enter it. With parallel sessions alive, provenance ages while the debrief runs.
The list is always single files. A folder passed to the engine is a blanket add
that carries the foreign work Step 4 excluded; the engine refuses folders for
that reason.

- **Stale-copy check, for every file on the list:** run
  `scripts/git-locked git fetch origin` first, then read the removed lines of
  `git diff origin/main -- <file>` and keep only those that also exist in
  `git show HEAD:<file>`: a line on both `HEAD` and `origin/main` that the
  working copy drops, and that this session did not mean to remove, is a stale
  copy overwriting newer work (lines only on origin are upstream additions and
  are not a hit). On a hit, stop and show the lines to the operator; merge only
  with their approval (`shared-tree-commit` in
  `skills/_improvements/known-patterns.md`).

The whole chain (index guard, staging, commit, fetch, rebase, push, content
verification) lives in `scripts/debrief-push.sh` and runs under `scripts/git-locked`,
which serializes git operations between parallel sessions on the same clone. **Never
rebuild the chain inline or from memory: run the script**, one quoted file per
argument:

```bash
scripts/git-locked scripts/debrief-push.sh "daily-log/2026-03-14-jane-doe.md" "memory/MEMORY.md" "memory/project_website.md"
```

The commit subject is built by the script (`debrief: <date> <time> (<slug>)`, the
slug resolved from `operators/` exactly as Step 0 does), so nothing from Step 0 needs
to be carried into this invocation.

What the script does, in order: refuses to run off `main` or on top of an unfinished
merge or rebase; stops if the index already holds staged paths outside the allow-list
(another session's work would ride into a plain commit); stages and commits; fetches;
if origin moved, rebases in place when the tree is clean, or in a temporary worktree
when the tree holds uncommitted work, so that work is never touched; pushes; then
verifies **by content** that every line the local commits added or removed is
reflected on `origin/main`, because a push's exit code proves nothing about what a
rebase kept.

### Common outcomes

- **exit 0, `PUSHED`**: done. The session is on the shared `main`, verified.
- **exit 0, `PUSHED-VIA-WORKTREE`**: done, through the temporary worktree; work in
  progress in the main tree stayed intact. If the script also printed
  `LOCAL-MAIN-DIVERGED`, local `main` still points at the pre-rebase commits and
  **will not realign by itself**: follow the instruction it printed (under the lock,
  `scripts/git-locked git reset --keep origin/main`, never a rebase; the why is in
  `reference/push-outcomes.md`) and note it in the log. If the reset refuses
  (`REALIGN-BLOCKED` included), follow "Realign refused" in the same file.
- **exit 0, `LOCAL-ONLY`**: no remote yet, commit kept on this machine. Normal before
  the first push of a fresh brain; finish `SETUP.md`.
- **exit 75**: the lock is held by another live session. Retry on a later tool turn;
  never remove the lock by hand.

**Any other exit (2, 3, 4, 10, 20, 21, 40, 41, 50, 64, 65, or one not listed): open
`skills/session-debrief/reference/push-outcomes.md` and follow the procedure for
that code.** The script prints the path. Do not improvise: exit 41 never closes a
session (the push looked fine but a change did not fully land on origin, an addition
missing or a deletion that did not stick), exits 20 and 21 are resolved *inside* the
stopped rebase (never `--skip` as the fallback of a failed `--continue`, never a
bare `rebase --abort` on the main tree), and a code outside the table is an anomaly
of the script to investigate, not an outcome. A network failure is not one of those
anomalies: it has its own outcome (exit 50, `FETCH FAILED`), the commit stays, the log
records it, and there is no silent retry.

### Team options

Two behaviours of the engine choose in place of a human, and are therefore off by
default. A team that wants them turns them on per clone with `git config` and records
the decision in its `docs/GOVERNANCE.md`:

- `git config brain.debrief.autoTake true`: on a conflict in the temporary worktree
  over a `daily-log/` or `memory/` file, take origin's side when every line of the
  local side already exists there (the typical case: a stale replay of a debrief that
  reached origin in a more complete form). Nothing is lost by construction, and every
  take is declared with an `AUTO-TAKE:` line. Files with unique lines on both sides
  still stop for a human.
- `git config brain.debrief.realign true`: after a `PUSHED-VIA-WORKTREE`, move local
  `main` to `origin/main` with `reset --keep`, which keeps uncommitted work and refuses
  when it would touch it.

---

## Step 6: Confirm

Close with one short message covering these things, in plain language:

- the daily-log file that was written, by name;
- the memory items updated, or "no memory changes this session";
- any content commits from Step 4, listed by subject;
- the engine outcome, explained rather than named: "committed and pushed, `main` is
  shared" beats "exit 0";
- when Step 0 found a feature branch in a linked worktree: "branch work committed on
  `<branch>` in its worktree; `/ship` opens the PR when the work is done".

If the outcome was `DEFER` or `PUSH-RACE`, say explicitly that the work is safe
locally and what will happen next, so nobody goes hunting for a lost session.

---

## Rules

- **Allow-list staging only.** Never `git add .`, `git add -A`, or a blanket add of
  `daily-log/` and `memory/`.
- **Listed paths never ride the debrief commit.** A `structural` or `sensitive` path
  goes to a branch (feature or proposal) or stays `Pending:`; it never lands on `main`
  from here.
- **Never force-push.** Not to recover from `PUSH-RACE`, not to tidy history, never.
- **Never skip hooks** (`--no-verify`).
- **Never resolve a conflict silently.** The operator chooses; you apply.
- **Never abort onto a dirty tree.** Use the safe abort in `reference/push-outcomes.md`
  (exit 20), and respect its `STOP`.
- **Never `--skip` as the fallback of a failed `--continue`.** The two legitimate
  skips are in `reference/push-outcomes.md`; the session commit is never skipped.
- **Never stash, checkout, or restore over uncommitted work.** If it is in the tree
  and you did not write it, leave it alone. The single exception: files already
  byte-identical to `origin/main` that block a realignment, released through
  "Realign refused" in `reference/push-outcomes.md` after the operator's explicit ok.
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
