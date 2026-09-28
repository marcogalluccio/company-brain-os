---
name: ship
description: |
  Opens or updates the pull request for the active feature branch with the
  commits accumulated since main. The daily flow does not use this: daily
  work lands on main through /session-debrief. Part of the governance pack:
  only relevant once docs/GOVERNANCE.md step 2 (feature branches) is
  adopted, and it needs an authenticated gh CLI.
  Use when the operator says: ship, /ship, open the pr, raise the pr.
---

# ship

Promote a feature branch's accumulated commits to a pull request. This is
the other half of `docs/GOVERNANCE.md` step 2: structural work that earned a
branch and a second pair of eyes gets closed out here, not through the
debrief. It is on-demand, not tied to any session boundary; a feature
branch can live for days and close with a single PR whenever it's ready.

## Step 0: Resolve the operator and detect state

The operator-resolution block, identical to `skills/session-debrief/SKILL.md`:

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

On `IDENTITY ERROR`, stop the skill and show the message exactly as it
printed. Never guess, never derive a slug from the git name itself: the
registry rule in `operators/CLAUDE.md` is binding here too.

Then detect which branch this is:

```bash
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "current=$CURRENT_BRANCH"
```

`/ship` takes an optional argument, the branch to ship (`/ship <branch>`).
The argument wins over the current directory: when it is given, the branch
is that one wherever the shell is, never the branch of the cwd.

**With an argument.** Find the worktree that has the branch checked out and
work from there without asking: naming the branch was the choice.

```bash
TARGET_BRANCH="<the branch named in the invocation, as literal text>"
# porcelain prints "worktree <path>" two lines above "branch refs/heads/<name>";
# grep -Fx matches the branch line literally (a "." in the name is not a
# wildcard), then grep/cut pull the path rather than awk, so the snippet
# holds no positional parameters; cut -f2- keeps a path with spaces whole
WT_PATH=$(git worktree list --porcelain | grep -B2 -Fx "branch refs/heads/$TARGET_BRANCH" | grep "^worktree " | cut -d" " -f2-)
echo "worktree=${WT_PATH:-none}"
```

- `WT_PATH` found: `cd "$WT_PATH"`, recompute `CURRENT_BRANCH`, say
  "Shipping `<branch>` from `<path>`", and continue to Step 1. If
  `$TARGET_BRANCH` matches `*/proposals-*` (a proposal pull request from
  `skills/session-debrief/reference/split-paths.md` Procedure B), stop
  instead: "`<branch>` is a proposals branch; it already gets its own PR
  from that flow. Use `/pr-review` to review it, not `/ship`."
- The branch exists (`git rev-parse --verify --quiet "refs/heads/$TARGET_BRANCH"`
  succeeds) but no worktree has it: stop and ask. Shipping means checking the
  branch out somewhere, and the main tree stays on `main`; offer
  `git worktree add <path> <branch>` and rerun.
- The branch does not exist: stop. "Branch `<name>` not found. Feature
  branches checked out in worktrees: <the `git worktree list` lines that are
  not `main` and not detached>."

**Without an argument, on `main`:** do not stop empty-handed. The main tree
stays on `main` in the daily flow, so the feature branch may well be ready in
a worktree. Run `git worktree list`. If it shows worktrees on feature branches
(exclude the main tree, any detached one, and any branch matching
`*/proposals-*`, which belongs to the proposal pull request flow in
`skills/session-debrief/reference/split-paths.md` Procedure B and already has
its own PR), list them and **ask** which to ship; never move to one silently,
the choice is the operator's when no argument was given:

> "You're on `main` (the daily flow lands there through the debrief), but
> there are feature branches in worktrees: <branch, path>. Ship one of these?
> Name it, or rerun `/ship <branch>`."

On the answer, `cd` into the chosen worktree, recompute `CURRENT_BRANCH`, and
continue to Step 1. If there is no such worktree, stop:

> "You're on `main`: the daily flow already lands there through the
> debrief, and there is no feature branch in a worktree. `/ship` is only for
> feature branches (`docs/GOVERNANCE.md` step 2)."

**Without an argument, on any other branch:** confirm this is the branch to
ship before doing anything else:

> "You're on `$CURRENT_BRANCH`. Ship this branch as a PR?"

Wait for confirmation.

## Step 1: Working tree check

```bash
git status --short
```

If there are uncommitted changes under `daily-log/` or `memory/`: they never
belong to the PR. Offer to run a debrief first: from a feature branch in a
worktree, `/session-debrief`'s branch guard commits only the branch's own work
there and takes the daily log and memory to `main` from the main tree. If the
operator would rather not, say plainly that those changes will not be part of
the PR.

If there are uncommitted changes outside `daily-log/` and `memory/`: state
plainly that they stay out of the PR too. This skill never commits on the
operator's behalf outside the debrief path above.

## Step 2: Commits to ship

```bash
git fetch origin main --quiet
COMMITS=$(git log origin/main..HEAD --oneline)
BEHIND=$(git rev-list --count HEAD..origin/main)
```

If `$COMMITS` is empty, there is nothing to ship. Say so, and mention
whether the branch is also behind (`$BEHIND` > 0 means it's stale but
carries no commits of its own; `$BEHIND` = 0 means it's simply aligned with
main). Exit either way.

Everything so far, Step 0's identity check, the branch detection, Step 1's
working-tree check, and the fetch/count above, is plain git and never
touches `gh`. From here on it does: the stale-branch path just below can
call `gh pr list`, and Step 3 always does, so check the CLI is ready before
going further. Run `gh auth status`. If it fails, say this skill needs an
authenticated `gh` CLI, point at the dependency matrix in the README, and
stop.

**If `$BEHIND` > 0 (the branch is stale, forked from an older `main`):**
the two-dot commit list above (`origin/main..HEAD`) stays correct even from
stale, it only ever shows the branch's own commits. The problem is the
file-changed count that comes next: a two-dot `diff --stat` would also
include everything `main` gained in the meantime, undone, which reads as a
phantom payload far larger than what the branch actually carries.

Check whether a PR is already open on this branch (the same check Step 3
runs, done early here to decide the stale-branch path):

```bash
EXISTING=$(gh pr list --head "$CURRENT_BRANCH" --state open --json number,url -q '.[0]')
```

- **If `$EXISTING` is non-empty (a PR is already open):** do not offer a
  rebase. Rewriting commits that are already pushed means the next push gets
  rejected as non-fast-forward, and this skill never force-pushes. Use
  `git diff --stat origin/main...HEAD | tail -1` (three dots, merge-base)
  for the file-changed count only, never for the commit list. Say plainly:
  "The branch is behind main, but it already has an open PR, so I'm not
  rebasing (it would break the next push). The file-changed count below
  uses the three-dot diff so it doesn't include main's unrelated changes."
  When `main` truly has to enter the branch (GitHub reports conflicts, or
  the tests must rerun on the new `main`), the positive road is
  `git merge origin/main` on the branch: it adds one merge commit, rewrites
  no SHA, so the next push stays fast-forward, and the squash merge absorbs
  it at the end. A force-push, `--force-with-lease` included, is never the
  answer here without an explicit question in chat.
- **If `$EXISTING` is empty (no PR yet):** offer a choice. "The branch is
  behind main by N commits. I can rebase onto `origin/main` first (needs a
  clean tree), or show the real payload with a three-dot diff without
  rebasing. Which do you want?" A rebase here needs the tree clean per Step
  1; if it isn't, resolve that first. After a rebase, `$BEHIND` becomes 0
  and the rest of this step proceeds on two dots as normal.

Otherwise (`$BEHIND` = 0), show the operator: the commit count and one-line
subjects from `$COMMITS`, and the file-changed count from
`git diff --stat origin/main..HEAD | tail -1`.

## Step 3: Existing PR check

```bash
EXISTING=$(gh pr list --head "$CURRENT_BRANCH" --state open --json number,url -q '.[0]')
```

If non-empty, this run pushes to update that PR; it never opens a duplicate.
Skip the `gh pr create` call in Step 4 and go straight to the push.

## Step 4: Confirm, push, create

Ask once, with the commit count and the title:

> "Open a PR with N commits onto `main`? Title: `$TITLE` (default: the
> branch name after the first `/`; tell me if you want something else)."

Wait for confirmation, then run:

```bash
git push -u origin "$CURRENT_BRANCH"
BODY_COMMITS=$(git log origin/main..HEAD --pretty=format:'- %s' --reverse)
gh pr create --title "$TITLE" --base main \
  --body "$(printf 'Feature branch %s into main (squash).\n\nCommits:\n%s\n' "$CURRENT_BRANCH" "$BODY_COMMITS")"
```

If a PR already existed (Step 3), skip `gh pr create` and only run the
`git push -u`: that alone updates the existing PR.

On any push or create failure, show it plainly and stop. No silent retries.

Close with: "PR is up at `<URL>`. Run `/pr-review <n>` to review and merge
it." Then, informational only, never run automatically: after the PR
merges, `git worktree remove <path>` if the branch lived in one, then
`git branch -D <branch>` to drop the local branch. `/pr-review`'s merge gate
already deletes the remote branch (`--delete-branch`); these two are local
cleanup only, and only worth mentioning, never worth doing here. One expected
message on that path: if the merge prints `fatal: 'main' is already used by
worktree`, the merge on GitHub already succeeded and the error is about the
local checkout of `main` only; verify with `gh pr view <n> --json state`
(expect `MERGED`) rather than rerunning the merge.

## Rules

- **One invocation, one PR action.** Open a new PR or update an existing
  one, never both, never more than one PR per run.
- **Never pushes to `main`.** This skill only ever pushes the feature
  branch itself.
- **Never auto-merges.** Merging happens through `/pr-review`, so the
  operator sees the diff first.
- **Never force-pushes.** If the push is rejected because the remote
  diverged, stop and ask; do not rebase and force past it. When `main` has to
  enter a branch with an open PR, merge it in (Step 2); a rebase of pushed
  commits is never offered.
- **Works from a worktree when the branch lives in one.** An explicit
  `/ship <branch>` moves there without asking; on `main` without an argument,
  the skill lists the feature worktrees and asks, never moves silently.

## Self-improvement

At the end of the run, check it against these friction triggers: **avoidable
round-trip · improvisation · breakage · token waste · operator correction**
(full definitions in `skills/_improvements/capture.md`). If at least one fired,
ask the operator "there was friction on X, should I log it?"; on their ok,
append an entry to `skills/_improvements/friction-log.md` in the format
`capture.md` defines. Clean run: say nothing. Never self-edit this skill;
improvements go through `/skill-improve`.
