# Governance

`CLAUDE.md`'s daily git cycle is the default: everyone works directly on `main`,
`/session-debrief` commits and pushes at the close of a session, nothing waits on
review. That default is enough for most companies for a long time.

This file is the opt-in growth layer for when it isn't. It covers three independent
steps: a repo-admin can activate any one, any combination, or none of them, in any
order. None of them change the promise in `CLAUDE.md`: daily work still lands on `main`
through the debrief unless you deliberately route a specific change somewhere else.

## 1. Branch protection

**When you need it:** multiple operators pushing straight to `main`, and you want a
safety net against destructive mistakes (a force-push, a deleted branch, a rewritten
history) without slowing anyone's daily push down.

**What it costs:** nothing to the daily workflow. This is a guardrail on the existing
direct-push habit, not a gate in front of it. Setup is one API call, made once, by
someone with admin rights on the repo.

**How to activate:**

```bash
gh api -X PUT "repos/{owner}/{repo}/branches/main/protection" \
  -F required_linear_history=true -F allow_force_pushes=false \
  -F allow_deletions=false -F enforce_admins=true \
  -F required_status_checks=null -F restrictions=null -F required_pull_request_reviews=null
```

This turns on linear history, blocks force-push, blocks branch deletion, and applies
the rule to admins too (`enforce_admins=true`, so nobody is quietly exempt). It
deliberately leaves `required_status_checks`, `restrictions`, and
`required_pull_request_reviews` empty: no CI gate, no required reviewers, nobody is
blocked from pushing straight to `main`.

**Plan requirement:** this call only succeeds on a public repository, or a private one
on a paid plan. On a free personal account or a free org, running it against a private
repo fails with a 403 and this exact body: `Upgrade to GitHub Pro or make this
repository public to enable this feature.` Branch protection (and rulesets, its newer
form) on private repos needs GitHub Pro for a personal account, or a paid plan for an
organization; there is no free-tier path around it. Two honest options: upgrade the
plan, or skip this step and accept the trade-off, steps 2 and 3 below still work in
full without it. If you do upgrade later, the settings above are exactly the ones that
ship, nothing to reconsider once the feature is available.

**How it interacts with the daily flow:** it doesn't change it. `/session-debrief`
still pushes directly to `main` every session, exactly as `CLAUDE.md` describes. This
step only makes a handful of destructive operations impossible, even by accident. It is
a floor under the daily flow, not a gate in front of it.

## 2. Feature branches + /ship

**When you need it:** structural work, changes to `skills/`, `scripts/`, the git
plumbing, or the protected files described below, that you want a second pair of eyes
on before it lands, instead of it going straight to `main` through the debrief like
everything else.

**What it costs:** a slower loop for that specific work: branch, PR, review,
squash-merge, instead of a same-session push. It is only worth it once structural
changes are frequent or risky enough that review earns its cost.

**How to activate:** name the structural paths in `.github/structural-paths.txt`. The
file ships with every line commented out, which keeps the mechanism inert; uncomment
the recommended block, or write your own, and the debrief starts refusing to commit
those paths on `main`. Cut a feature branch for the structural change, work there, open
a pull request when it's ready, squash-merge once it's approved. The `/ship` skill
(ships with the skills suite) automates opening the PR from the commits accumulated on
the branch, and `/session-debrief` offers the branch itself the moment it classifies a
path as structural (the procedure is in
`skills/session-debrief/reference/split-paths.md`).

**Not every `CLAUDE.md` is structural.** Two categories, treated differently on purpose:

- **Protected files**: the few system files that decide how every agent behaves,
  wherever it is working. In this template that is the root `CLAUDE.md`,
  `memory/CLAUDE.md`, `daily-log/CLAUDE.md`, and `operators/CLAUDE.md`. Your brain may
  have more (a `CLAUDE.md` for a shared tool, a schema file every skill reads); you name
  them in `.github/structural-paths.txt`. Protected files travel through a feature
  branch, always.
- **Area `CLAUDE.md` files** (`areas/<name>/CLAUDE.md`): they describe one folder and
  they change every time the folder does. They keep landing on `main` through the
  debrief, after explicit approval in chat, exactly as before. Routing them through a
  branch is the fastest way to stop them being updated at all: the frequent, small,
  routing-level edits are the ones that never get a PR opened for them, and the drift
  piles up in the files that are supposed to be the map.

**Carve-outs.** A line starting with `!` in `.github/structural-paths.txt` exempts a path
even when a broader pattern would catch it. The recommended block exempts
`skills/_improvements/friction-log.md`: an append-only log of friction is a note, not a
skill edit, and it is the one file under `skills/` we suggest every operator be able to
push from a debrief. Which files earn a carve-out is your team's call.

**How it interacts with the daily flow:** this is the one step that visibly changes
behavior, but only for the paths you list. Daily work, the content most sessions touch
in `areas/`, `memory/`, `daily-log/`, keeps landing on `main` via the debrief exactly as
before. Nothing forces every change through a branch; the list decides, path by path,
which class of edits earns the extra step.

## 3. Sensitive scopes + CODEOWNERS

**When you need it:** some paths (client materials under NDA, financials, whatever your
company treats as sensitive) need a specific person's eyes on every change that touches
them, and you want that routed automatically instead of remembered by hand.

**What it costs:** a `.github/CODEOWNERS` file to write and keep current as scopes and
operators change, a pattern list, one flag in the operator registry, one `git config`
per clone, plus the discipline described below to keep it honest.

**How to activate, the map:** add a `.github/CODEOWNERS` file mapping paths to GitHub
usernames, for example:

```
areas/clients/big-account/     @jane-doe
areas/operations/finance/      @jane-doe @finance-lead
areas/finance/                 @jane-doe @finance-lead
operators/                     @jane-doe
```

Anyone who opens a pull request touching one of those paths automatically gets the
listed usernames requested as reviewers.

**CODEOWNERS is a map, not enforcement.** What it does: routes pull request review,
GitHub requests the listed people automatically when a PR touches their paths. What it
does not do: control read access inside the repo. A GitHub collaborator with access to
the repo can read every file in it, CODEOWNERS included, regardless of which paths list
their name. If a scope must not be visible to some operators at all, CODEOWNERS is the
wrong tool: use `private/` (gitignored, never leaves the machine it was written on) or
split the sensitive scope into its own repo with its own collaborator list. And it has
nothing to say about work that lands on `main` directly through the debrief: CODEOWNERS
only fires on pull requests. The recipe below exists for exactly that gap.

**Optional: scope tags.** If you want the root `CLAUDE.md` to say who owns each folder,
append `(scope: shared)` or `(scope: <operator-slug>)` to a bullet of its Structure
section:

```
- `areas/finance/`: money. (scope: jane-doe)
```

The scanner `/system-checkup` runs then compares each tag against CODEOWNERS: `shared`
expects two or more usernames on that path, a slug expects exactly one, the `github`
value of `operators/<slug>.md`. It reports a disagreement as a `SCOPE` error and a
tagged path with no CODEOWNERS line as an `info`. This comparison only runs when
`.github/CODEOWNERS` exists; without it the scanner skips scope tags entirely, so a
team that tags bullets but has not adopted CODEOWNERS gets silence, not a finding.
Tags are optional, untagged bullets are never checked, and the template ships none of
its own, so a team that does not want them never sees a `SCOPE` finding.

**How to activate, the recipe.** Four pieces ship with the template and stay inert until
the first one has an active line:

1. **The pattern list**, `.github/sensitive-paths.txt`: one glob per line, `*` also
   matches `/`, `!pattern` is an exception that always wins, `#` is a comment. Keep it a
   subset of the CODEOWNERS scopes routed to a single reviewer.
2. **The owners**, in the registry: set `sensitive_owner: true` in the frontmatter of
   `operators/<slug>.md` for every operator allowed to push those paths straight to
   `main`. Everyone else is a proposer for them. More than one owner is fine; zero
   owners with an active list means nobody can push them directly, which
   `/system-checkup` reports.
3. **The local hook**, `githooks/pre-push`: refuses a push to `main` that touches a
   listed path unless the pushing identity resolves, through `operators/`, to a
   sensitive owner. Activate it once per clone:

   ```bash
   git config core.hooksPath githooks
   ```

   Nothing here names a person: the hook reads the registry, so adding an owner is a
   frontmatter edit, never a hook edit.
4. **The CI tripwire**, `.github/workflows/sensitive-tripwire.yml`: on every push to
   `main`, it runs `scripts/sensitive-tripwire-detect.sh` and opens a GitHub issue when
   a listed path was pushed by an account that is not a sensitive owner (matched on the
   `github` field of the registry), or when commits authored under an owner's git
   identity were pushed by someone else, which usually means a misconfigured
   `user.name`. It never reverts anything. Trigger it by hand once (Actions, "Run
   workflow") to prove it is alive. One caveat on inertness: the workflow file, once
   present, runs on each push to `main` whether or not the list is adopted, and while the
   list has no active line it reports no hit and opens nothing. What an unadopted repo
   gets is a short green run per push, not a notification.

**Proposal pull requests.** When `/session-debrief` finds an approved change on a
sensitive path and the operator is not a sensitive owner, it does not push it to `main`:
it moves the change onto a branch named `<slug>/proposals-YYYY-MM-DD`, pushes that, and
opens a pull request titled `[proposal] ...` (procedure in
`skills/session-debrief/reference/split-paths.md`). The PR body says whether any of the
files changed on `main` after the proposer's local base (a staleness flag: review those
with extra care). Two rules keep it honest: **the proposer never merges their own
proposal**, and a sensitive owner reviews it on whatever turnaround the team agrees on,
same day if you can, so proposals do not pile up. `/pr-review` lists proposals first and
refuses the merge gate to their author.

**State its limit plainly: this is detection plus discipline, not a wall.** A local hook
can be skipped with `--no-verify`, or avoided entirely by unsetting `core.hooksPath`; a
CI check only ever sees what reaches the remote, and by then the push has happened; and
unless the pattern list covers `operators/*` as well, an operator can add
`sensitive_owner: true` to their own registry file, land it on `main` as an ordinary
change, and be an owner from that commit on. That last one is why the recommended block
carries an `operators/*` line. What the recipe buys you is three chances to catch an
accident before it lands (the debrief classifier, the hook, the tripwire) and an audit
trail when one lands anyway. It raises the cost of touching a sensitive path by
accident; it does not make it impossible on purpose. If you need impossibility, the
tools are branch protection with required reviews (step 1, with
`required_pull_request_reviews` set), a separate repository, or `private/`.

**Keeping it coherent.** `scripts/governance-check.sh`, run by `/system-checkup`, reports
an active list with no owner, an owner without a `github` value, a clone without the
hook, a missing workflow, and drift between the pattern list and CODEOWNERS in both
directions.

### Offboarding checklist

When an operator leaves, don't just delete their file in `operators/`. Work through
this list:

1. **Revoke GitHub access.** Remove them as a collaborator on the repo (and on any repo
   split out under step 3's sensitive-scope pattern).
2. **Clean up CODEOWNERS and the operator registry.** Remove their username from
   `.github/CODEOWNERS`. Don't delete `operators/<slug>.md`: move it to
   `operators/archive/<slug>.md`, which keeps the slug reserved while taking the file out
   of the registry (only files directly in `operators/` resolve an identity). Daily logs
   and memory files may still reference that slug historically, and reusing it for a new
   operator would make old references ambiguous. If they were a `sensitive_owner`, the
   move also revokes that, and `/system-checkup` will tell you if nobody owns the
   sensitive scopes any more.
3. **Reassign `owner:` fields.** Every `memory/` file whose frontmatter `owner:` pointed
   at the departed operator's slug needs a new owner, someone who inherits that work, or
   an explicit note that it's unowned for now.
4. **Remember what stays on their machine.** The departed operator keeps their local
   clone of the repo. Revoking GitHub access stops future pulls; it does not retroactively
   remove what already reached their disk. Anything that should never have left the
   company in the first place belongs in `private/` (gitignored, never synced) precisely
   so it never reached that clone to begin with. Everything else in the repo, they
   already had, because it was already shared with every operator by design.
