# Splitting listed paths away from `main`

Reference for `/session-debrief` Step 4. Open it only when
`scripts/classify-paths.sh` reported a `structural` or `sensitive` path; the
classification itself and the common outcomes stay in `SKILL.md`.

Two procedures, one per class. Both move an approved change out of the main working
tree onto a branch, commit it there, and put the main tree back to what `HEAD` holds,
so the debrief commit that follows carries only what may land on `main`.

Substitute every `<placeholder>` as literal text before running a block. The blocks
never use shell positional parameters (dollar sign followed by a digit) on purpose:
Claude Code replaces those with the skill's invocation arguments.

## Before either procedure

- The change must have been approved in chat (Step 3). A listed path that was not
  approved is left where it is, uncommitted, and named in the daily log as
  `Pending:`.
- **Semantic atomicity.** If the listed change and the rest of the session's content
  cannot stand apart (one half breaks without the other), do not split: put all of the
  session's content work on the feature branch, and let the daily log and memory
  still land on `main` through the debrief from the main tree (Step 0's branch guard,
  feature-branch case). Splitting a coupled change leaves `main` inconsistent until the
  PR merges.
- A fresh worktree contains no gitignored files (`private/`, generated indexes). If the
  change depends on one, say so before moving it.

## A. `structural`: feature branch in a worktree

Every operator, no exceptions. The branch belongs to the active operator and is
closed by `/ship`, never by a push from the debrief.

```bash
cd "$(git rev-parse --show-toplevel)"
WT="$(mktemp -d "${TMPDIR:-/tmp}/brain-feature.XXXXXX")"
git fetch origin main --quiet
git worktree add "$WT" -b "<slug-from-step-0>/<short-topic>" origin/main
```

For each structural path (repeat the three lines per file, then commit once):

```bash
mkdir -p "$WT/$(dirname "<path>")"
cp "<path>" "$WT/<path>"
git -C "$WT" add "<path>"
```

```bash
git -C "$WT" commit -m "<subject>"
```

Then put the main tree back, file by file, **only if the copy on the branch is still
byte-identical to the one in the tree**. A file that changed in between (another
session writing to it) stays as it is, and the log says so:

```bash
if cmp -s "<path>" "$WT/<path>"; then
  if git ls-files --error-unmatch "<path>" >/dev/null 2>&1; then
    git restore --source=HEAD -- "<path>"
  else
    rm "<path>"
  fi
else
  echo "CHANGED DURING SPLIT: <path> differs from the copy just committed; left in the tree, note it in the log"
fi
```

The worktree stays: the work continues there and `/ship` opens the PR when it is ready.
Tell the operator the path of the worktree and the branch name. Never `git worktree
remove` it here.

## B. `sensitive` (non-owner): proposal pull request

Only when the classifier printed `sensitive`, which it does for an operator without
`sensitive_owner: true`. The branch is dated and reusable within the day: a second
sensitive change on the same day stacks on the same proposal.

```bash
cd "$(git rev-parse --show-toplevel)"
PROP="<slug-from-step-0>/proposals-$(date +%Y-%m-%d)"
WT="$(mktemp -d "${TMPDIR:-/tmp}/brain-proposal.XXXXXX")"
git fetch origin main --quiet
if git show-ref --verify --quiet "refs/remotes/origin/$PROP"; then
  git worktree add "$WT" -B "$PROP" "origin/$PROP"
else
  git worktree add "$WT" -b "$PROP" origin/main
fi
```

Copy each approved sensitive path in, recording which ones moved on `origin/main`
after this clone's `HEAD` (a stale base: the reviewer must look at those with extra
care):

```bash
STALE=""
for f in <approved-sensitive-paths>; do
  if [ "$(git rev-parse -q --verify "HEAD:$f" 2>/dev/null)" != "$(git rev-parse -q --verify "origin/main:$f" 2>/dev/null)" ]; then
    STALE="$STALE $f"
  fi
  mkdir -p "$WT/$(dirname "$f")"
  cp "$f" "$WT/$f"
  git -C "$WT" add "$f"
done
git -C "$WT" commit -m "proposal: <subject> (<slug-from-step-0>)"
git -C "$WT" push -u origin "$PROP"
```

Open the PR only if none is open on that branch yet (a stacked proposal updates the
existing one through the push above):

```bash
if [ -z "$(gh pr list --head "$PROP" --state open --json number -q '.[0]')" ]; then
  gh pr create --head "$PROP" --base main \
    --title "[proposal] <subject> (<slug-from-step-0>)" \
    --body "Proposal for sensitive paths from a debrief. A sensitive owner reviews and merges it; the proposer never merges their own.${STALE:+ STALE: these files changed on main after the proposer's local base, review them with extra care:$STALE}"
fi
```

If `gh` is not available or not authenticated, stop after the push and tell the
operator to open the PR from the branch by hand, with the same title and the staleness
note if `STALE` is non-empty.

Then put the main tree back (the proposed content now lives on the PR), guarding each file
the way Procedure A does: only restore or remove it if the copy in the main tree still
matches byte-for-byte what was committed on the branch. A file that changed in the meantime
stays as it is:

```bash
for f in <approved-sensitive-paths>; do
  if cmp -s "$f" "$WT/$f"; then
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      git restore --source=HEAD -- "$f"
    else
      rm "$f"
    fi
  else
    echo "CHANGED DURING SPLIT: $f differs from the copy just committed; left in the tree, note it in the log"
  fi
done
git worktree remove "$WT"
```

A file left in the tree by the guard is handled the same way as a listed path whose split the
operator declined: it stays uncommitted and today's daily log names it as `Pending:`.

Say in chat: the PR URL, whether `STALE` was non-empty, and that a sensitive owner
merges it. **The proposer never merges their own proposal**, and `/pr-review` enforces
that at its merge gate.
