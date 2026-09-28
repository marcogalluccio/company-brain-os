---
name: pr-review
description: |
  PR triage and merge: lists open PRs, summarizes diffs and review state, merges
  one PR at a time with an explicit gate. Part of the governance pack: inert
  until docs/GOVERNANCE.md is adopted, and needs an authenticated gh.
  Use when the operator says: pr review, /pr-review, review pr, open prs, merge pr.
---

# pr-review

PR triage and merge. Lists open pull requests, summarizes one on request, and
merges through an explicit confirmation gate. This is one of the three
governance-pack steps in `docs/GOVERNANCE.md`: it does nothing until a repo
admin has activated feature branches (step 2) or CODEOWNERS (step 3) there,
and it needs the `gh` CLI authenticated against the repo.

## Precondition

Run `gh auth status`. If it fails, say this skill needs an authenticated `gh`
CLI, point at the dependency matrix in the README, and stop. Do not attempt
any of the steps below without it.

## Mode A: no argument, list and summarize

```bash
gh pr list --state open --json number,title,author,createdAt,reviewDecision,mergeStateStatus,headRefName
```

For each PR, show one line: number, title, author, age (from `createdAt`),
review decision (`APPROVED`, `CHANGES_REQUESTED`, or none), merge state
(`CLEAN`, `BLOCKED`, `BEHIND`, `DIRTY`). Highlight any PR whose merge state is
blocked or dirty.

A PR whose `headRefName` matches `*/proposals-*` is a proposal: a non-owner's
change on a sensitive path, waiting for a sensitive owner (`docs/GOVERNANCE.md`
step 3). List proposals first, prefixed `[proposal]`, and say who they are
waiting on: teams usually agree a turnaround for proposals, often the same day,
and a proposal that has aged past it is the first finding of this run.

Close with: "Pick a PR number to focus on, or call `/pr-review <n>` directly."

## Mode B: `/pr-review <n>`, focus on one PR

### Step 1: Header

```bash
gh pr view <n> --json title,author,baseRefName,headRefName,state,mergeStateStatus,reviewDecision,statusCheckRollup,files
```

Show title, author, base and head branch, state, merge status, review
decision, status checks, and the list of changed files.

### Step 2: Diff

```bash
gh pr diff <n>
```

If the diff is longer than 500 lines, show the first 200 and the last 100
lines with a `[ … skipped … ]` marker between them, instead of the full diff.

### Step 3: Map the scope (if CODEOWNERS exists)

If `.github/CODEOWNERS` exists in the repo, map the changed files (from
Step 1) against it and tell the operator whose review the PR is routed to.
Per `docs/GOVERNANCE.md` step 3, CODEOWNERS is a map, not enforcement: it
tells you who GitHub will request as a reviewer, it does not by itself block
or allow a merge. State it that way, don't imply the file is a gate.

If `.github/CODEOWNERS` does not exist, skip this step silently: CODEOWNERS
is opt-in, its absence is a normal, unconfigured state.

### Step 4: Ask for action

Offer exactly these options, nothing more:

- `merge`: squash-merge and delete the branch
- `comment <text>`: leave a review comment, `gh pr comment <n> --body "<text>"`
- `request-changes <text>`: request changes formally, `gh pr review <n> --request-changes --body "<text>"`
- `close`: close without merging, `gh pr close <n>`
- `skip`: exit without taking any action

## Merge gate

Before running anything, show the exact command that will run and what it
does (PR number, squash, branch deletion, target branch), then wait for a
pointed "ok". Never merge on momentum carried over from earlier in the
conversation: an earlier "yes let's merge that" is not this gate.

**Proposal gate.** If the head branch is a proposal (`*/proposals-*`), checks run
before anything else, all read from the registry, never from a name written here:

```bash
HEAD_REF=$(gh pr view <n> --json headRefName -q .headRefName)
case "$HEAD_REF" in
  */proposals-*)
    ME_SLUG=$(scripts/lib/operator-registry.sh resolve) || exit 1
    ME_LOGIN=$(scripts/lib/operator-registry.sh field "$ME_SLUG" github | sed 's/^@//' | tr '[:upper:]' '[:lower:]')
    AUTHOR=$(gh pr view <n> --json author -q .author.login | tr '[:upper:]' '[:lower:]')
    if [ -z "$AUTHOR" ]; then
      echo "PROPOSAL GATE: the pull request's author could not be read; the gate cannot be evaluated."
      exit 1
    fi
    if [ "$AUTHOR" = "$ME_LOGIN" ]; then
      echo "PROPOSAL GATE: you opened this proposal; a sensitive owner merges it, never the proposer."
      exit 1
    fi
    if ! scripts/lib/operator-registry.sh is-sensitive-owner "$ME_SLUG"; then
      echo "PROPOSAL GATE: operators/$ME_SLUG.md does not declare sensitive_owner: true; only a sensitive owner merges a proposal."
      exit 1
    fi
    ;;
esac
```

On any `PROPOSAL GATE` line, stop and show it. Do not offer `merge` for that PR;
`comment`, `request-changes`, `close` (own proposal only, with a reason) and `skip`
stay available. On an `IDENTITY ERROR` from the registry, stop as well: the rule in
`operators/CLAUDE.md` is binding here too.

If the PR's head branch (`headRefName` from Step 1) is checked out in a local
worktree, remove the worktree first, or the local branch deletion below
fails:

```bash
HEAD_REF=$(gh pr view <n> --json headRefName -q .headRefName)
# The porcelain listing prints, per worktree, a "worktree <path>" line, a HEAD
# line, then "branch refs/heads/<name>": the path sits two lines above the match.
WT_PATH=$(git worktree list --porcelain | grep -B2 -Fx "branch refs/heads/$HEAD_REF" | grep "^worktree " | cut -d" " -f2-)
[ -n "$WT_PATH" ] && git worktree remove "$WT_PATH"
```

Then, once the operator has given the pointed "ok":

```bash
gh pr merge <n> --squash --delete-branch
```

Squash keeps linear history, matching `docs/GOVERNANCE.md` step 1. There is
no `--admin` flag here: if branch protection on the repo requires reviews
that this PR does not have, the merge simply fails until the review exists.
Report that outcome honestly, don't look for a way around it.

## Post-merge

```bash
git fetch origin main --quiet
```

That's the only post-merge step. Never `checkout` or `pull` here: the local
working tree may hold uncommitted work from an in-progress session, and a
fetch only refreshes the remote-tracking ref without touching the tree.
Local `main` realigns on its own at the next `/sync` or debrief.

## Rules

- Always show the diff before offering merge. Never merge blind.
- One PR at a time. No bulk merges.
- A proposal is merged by a sensitive owner who is not its author. Never by the
  proposer, never by momentum.
- Never close someone else's PR without asking first. If it has problems,
  comment or request changes instead.
- Never force anything: no force-push, no bypassing branch protection.
- If branch protection requires reviews the PR doesn't have, the merge fails;
  report that plainly instead of reaching for a workaround.

## Self-improvement

At the end of the run, check it against these friction triggers: **avoidable
round-trip · improvisation · breakage · token waste · operator correction**
(full definitions in `skills/_improvements/capture.md`). If at least one fired,
ask the operator "there was friction on X, should I log it?"; on their ok,
append an entry to `skills/_improvements/friction-log.md` in the format
`capture.md` defines. Clean run: say nothing. Never self-edit this skill;
improvements go through `/skill-improve`.
