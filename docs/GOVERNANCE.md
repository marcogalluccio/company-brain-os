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

**When you need it:** structural work, changes to `skills/`, `CLAUDE.md` files, or
`scripts/`, that you want a second pair of eyes on before it lands, instead of it going
straight to `main` through the debrief like everything else.

**What it costs:** a slower loop for that specific work: branch, PR, review,
squash-merge, instead of a same-session push. It is only worth it once structural
changes are frequent or risky enough that review earns its cost.

**How to activate:** cut a feature branch for the structural change, work there, open a
pull request when it's ready, squash-merge once it's approved. The `/ship` skill (ships
with the skills suite) automates opening the PR from the commits accumulated on the
branch.

**How it interacts with the daily flow:** this is the one step that visibly changes
behavior, but only for the work you choose to route through it. Daily work, the content
most sessions touch in `areas/`, `memory/`, `daily-log/`, keeps landing on `main` via
the debrief exactly as before. Nothing forces every change through a branch; you decide,
change by change, which class of edits earns the extra step.

## 3. Sensitive scopes + CODEOWNERS

**When you need it:** some paths (client materials under NDA, financials, whatever your
company treats as sensitive) need a specific person's eyes on every pull request that
touches them, and you want that routed automatically instead of remembered by hand.

**What it costs:** a `.github/CODEOWNERS` file to write and keep current as scopes and
operators change, plus the discipline described below to keep it honest.

**How to activate:** add a `.github/CODEOWNERS` file mapping paths to GitHub usernames,
for example:

```
areas/clients/big-account/     @jane-doe
areas/operations/finance/      @jane-doe @finance-lead
```

Anyone who opens a pull request touching one of those paths automatically gets the
listed usernames requested as reviewers.

**How it interacts with the daily flow:** it layers on top of whichever flow the work
already travels through. If the touched path also happens to be routed through a
feature branch (step 2), CODEOWNERS decides who gets requested on that PR. It has
nothing to say about work that lands on `main` directly through the debrief: CODEOWNERS
only fires on pull requests.

**CODEOWNERS is a map, not enforcement.** What it does: routes pull request review,
GitHub requests the listed people automatically when a PR touches their paths. What it
does not do: control read access inside the repo. A GitHub collaborator with access to
the repo can read every file in it, CODEOWNERS included, regardless of which paths list
their name. If a scope must not be visible to some operators at all, CODEOWNERS is the
wrong tool: use `private/` (gitignored, never leaves the machine it was written on) or
split the sensitive scope into its own repo with its own collaborator list.

An optional recipe on top of CODEOWNERS is a hook or CI check that blocks a commit or
push touching a sensitive path unless it comes from an approved identity. It adds
friction and an audit trail, but state its limit plainly: it is bypassable. A local
hook can be skipped with `--no-verify`, or avoided entirely by unsetting
`core.hooksPath`; a CI check only ever sees what reaches the remote. Treat this pattern
as discipline and audit, not a wall: it raises the cost of touching a sensitive path by
accident, it does not make it impossible on purpose.

### Offboarding checklist

When an operator leaves, don't just delete their file in `operators/`. Work through
this list:

1. **Revoke GitHub access.** Remove them as a collaborator on the repo (and on any repo
   split out under step 3's sensitive-scope pattern).
2. **Clean up CODEOWNERS and the operator registry.** Remove their username from
   `.github/CODEOWNERS`. Don't delete `operators/<slug>.md`: move it to an archive
   location and keep the slug reserved. Daily logs and memory files may still reference
   that slug historically, and reusing it for a new operator would make old references
   ambiguous.
3. **Reassign `owner:` fields.** Every `memory/` file whose frontmatter `owner:` pointed
   at the departed operator's slug needs a new owner, someone who inherits that work, or
   an explicit note that it's unowned for now.
4. **Remember what stays on their machine.** The departed operator keeps their local
   clone of the repo. Revoking GitHub access stops future pulls; it does not retroactively
   remove what already reached their disk. Anything that should never have left the
   company in the first place belongs in `private/` (gitignored, never synced) precisely
   so it never reached that clone to begin with. Everything else in the repo, they
   already had, because it was already shared with every operator by design.
