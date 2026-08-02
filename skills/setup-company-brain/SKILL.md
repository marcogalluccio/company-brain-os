---
name: setup-company-brain
description: |
  Guided first-time setup of a company brain created from the Company Brain
  OS template: interviews the admin one question at a time, fills in the
  company context, registers the admin and every teammate, shapes the areas,
  seeds the first memory files, invites collaborators, and makes the first
  push. Idempotent and resumable: progress lives in SETUP-STATE.md, so an
  interrupted setup picks up where it stopped.
  Use when the operator says: setup, set up this brain, set up the company
  brain, /setup-company-brain, finish setup, resume setup, continue setup.
---

# /setup-company-brain

This is the guided path through the second half of `SETUP.md`: the admin answers
questions, you write the files, and the brain ends up in the same state a careful
manual run would leave it in, just without the operator having to hold nine steps in
their head at once.

**Scope.** This skill covers `SETUP.md` Steps 6 through 9, plus the smoke test in
Step 10: company context, the admin's own operator file, the areas, the first
projects, registering teammates, and the first push. The plumbing before that, Steps
1 through 5 (use the template, clone the repo, set git identity, register skills,
link the memory folder), is a **prerequisite**, not something this skill performs.
P1 checks that it is done; it never runs those steps on the operator's behalf, with
one exception: P8 repairs a missing memory symlink before declaring setup done. By
construction it cannot even start until Step 4 has registered it, since that is the
step that makes `/setup-company-brain` discoverable in the first place.

**Interview style.** Ask one question at a time, and wait for the answer before
asking the next one. Never lay out a wall of questions in a single message and ask
the operator to answer all of them at once; that is exactly the friction this skill
exists to remove.

**Push authority.** This skill makes its one git push to `main` in P7 (first push);
P6 (team registration) never writes to git, only sends GitHub collaborator
invitations. Neither is covered by the root `CLAUDE.md` carve-out, which
pre-authorizes `session-debrief`'s own commit-and-push and names nothing else. Every
push and every invitation this skill makes happens only after the operator's explicit
ok in chat, and P6 and P7 say so at the exact point where they ask for it.

**CLAUDE.md edits.** Root `CLAUDE.md` carries a `{{COMPANY_NAME}}` token on its first
line that P2 replaces with the company's real name. That edit is itself gated by the
root rule "never modify a `CLAUDE.md` file without the operator's explicit approval
first": P2 shows the exact replacement line and asks before writing it, rather than
folding it into a larger, harder-to-review diff.

---

## Setup state: SETUP-STATE.md

Progress lives in a state file at the repo root, `SETUP-STATE.md`. It is gitignored
and machine-written only: the skill writes and checks it, the operator never hand-edits
it.

```markdown
# Setup state
<!-- Written by /setup-company-brain. Tracks completed phases so an
     interrupted setup can resume. Local only (gitignored); deleted
     automatically when setup completes. -->
- [x] P1 preflight
- [ ] P2 company context
- [ ] P3 admin operator
- [ ] P4 areas
- [ ] P5 first projects
- [ ] P6 team registration
- [ ] P7 first push
- [ ] P8 smoke test and wrap-up
```

Rules:

- **On invoke, check for the file first.** If `SETUP-STATE.md` exists, this is a
  resume: announce "resuming from `<first unchecked phase>`" and continue from
  there, skipping every phase already checked. If it does not exist, this is a fresh
  run: proceed to P1, and once P1 passes, write the file above with only P1 checked.
- **A box is checked only after its writes are complete on disk.** Never check a
  phase in advance of doing its work, and never leave a phase unchecked once its
  writes are actually done; either state left standing is what breaks resumability
  for the next invocation.
- **Idempotence.** Before writing to any target file in any phase, look at what is
  already there. If it already holds non-placeholder content (a token already
  replaced, a section already filled in), show the operator what would change and
  ask before overwriting. This applies even on what looks like a fresh run: nothing
  stops an operator from filling in a few files by hand before ever invoking this
  skill, and a silent overwrite would throw that work away.
- **P8 deletes `SETUP-STATE.md` as its last write**, once the smoke test passes. A
  completed setup leaves no state file behind; its continued existence is itself the
  signal that setup is unfinished.

---

## P1: preflight

Run this once, at the very start of every invocation, resume or fresh, before
touching anything else. It confirms `SETUP.md` Steps 1 through 5 actually happened;
for the fatal cases (missing repo, missing origin, incomplete git identity), this
skill has no way to fix the gap, only to catch it before P2 builds on top of it.

```bash
TOP="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$TOP" ] || { echo "PRE-FLIGHT FAIL: not inside a git repo. Finish SETUP.md Step 2 first."; exit 1; }
cd "$TOP"
ORIGIN="$(git remote get-url origin 2>/dev/null)"
if [ -z "$ORIGIN" ]; then
  echo "PRE-FLIGHT FAIL: no origin remote. Finish SETUP.md Steps 1-2 first."
  exit 1
fi
case "$(printf '%s' "$ORIGIN" | sed -E 's#\.git$##')" in
  *marcogalluccio/company-brain-os)
    echo "PRE-FLIGHT FAIL: origin points at the public template, not your own repo."
    echo "You cloned the template itself. Delete this folder and start over from SETUP.md Step 1."
    exit 1 ;;
esac
GIT_NAME="$(git config user.name)"; GIT_EMAIL="$(git config user.email)"
if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
  echo "PRE-FLIGHT FAIL: git identity incomplete. Finish SETUP.md Step 3 first."
  exit 1
fi
BRAIN="$(pwd)"
CC_PROJECT="$HOME/.claude/projects/$(echo "$BRAIN" | sed 's/[^A-Za-z0-9-]/-/g')"
if [ -e "$CC_PROJECT/memory" ] || [ -L "$CC_PROJECT/memory" ]; then
  MEMLINK="present"
else
  MEMLINK="missing"
fi
echo "PRE-FLIGHT OK: origin=$ORIGIN admin-candidate=$GIT_NAME memory-symlink=$MEMLINK"
```

On any `PRE-FLIGHT FAIL`, stop the skill entirely and show the operator the exact
message the block printed. Do not attempt the missing step yourself: `SETUP.md`'s
numbered steps are written for the operator to run by hand, not for this skill to
paper over.

On `memory-symlink=missing`, warn the operator ("`SETUP.md` Step 5 is not done yet;
setup can continue, but auto-loaded memory will not work until you finish it") and
keep going. This is the one non-fatal case in the block.

The origin guard matches the URL's exact tail, not a substring: it strips a trailing
`.git` and then matches `*marcogalluccio/company-brain-os` only when that path
segment ends the string. An adopter whose own repo happens to be named, say,
`company-brain-os-acme` never false-trips it, because their origin's last segment is
`company-brain-os-acme`, not `company-brain-os`.

On `PRE-FLIGHT OK`, this phase is complete. If `SETUP-STATE.md` does not exist yet,
write it now, exactly as shown in the contract above, with P1 checked and every other
phase unchecked, then continue to P2.

---

## P2: company context

Ask these six questions, one at a time, in this order, and wait for each answer
before asking the next:

1. What's the company's name?
2. Give me a one-liner, the kind you'd put in a bio: what does this company do, in
   one sentence?
3. What do you actually do, a sentence or two longer than the one-liner: what's the
   product or service?
4. How do you make money: revenue model and primary channels?
5. What tools does the company live in day to day, beyond this repo?
6. Any house conventions this brain should always respect: language, tone, house
   style?

Before asking, check whether the tokens are still there:

```bash
grep -n '{{COMPANY_NAME}}\|{{COMPANY_ONE_LINER}}' "Company - Context.md" CLAUDE.md
```

**Idempotence.** If that grep finds nothing, both files were already filled in,
either by hand or by an earlier run of this skill. Show the operator the current
title, one-liner, and the four section bodies below, and ask whether to update them
or move straight to P3. Never overwrite silently, even on what looks like a fresh
run.

Writes, once all six answers are in:

- `Company - Context.md`: replace `{{COMPANY_NAME}}` in the title with answer 1,
  `{{COMPANY_ONE_LINER}}` with answer 2, and fill in `## What we do` (answer 3),
  `## How we make money` (answer 4), `## Tools we live in` (answer 5), and
  `## Conventions` (answer 6). Leave `## Team` exactly as shipped: it already points
  at `operators/`, which is where that answer actually lives, and nothing in this
  interview replaces it.
- Root `CLAUDE.md`, line 3, `Operational brain of {{COMPANY_NAME}}.`: this is a
  `CLAUDE.md` edit, gated by the root rule "never modify a `CLAUDE.md` file without
  the operator's explicit approval first." Show the operator the exact replacement
  line, `Operational brain of <answer 1>.`, on its own, and ask before writing it.
  Don't fold it into the same message as the `Company - Context.md` diff; it needs
  its own explicit yes.

Check the P2 box in `SETUP-STATE.md` once both files are written, or once the
operator explicitly chose to skip the update.

---

## P3: admin operator

The admin is whoever is running this setup: `GIT_NAME`, resolved in P1 from
`git config user.name`.

Ask, one at a time:

1. Display name: prefilled from `GIT_NAME`, confirm rather than retype. Show it and
   ask, "Is `<GIT_NAME>` right as your display name, or do you go by something else
   in this brain?" Whatever the operator confirms is what shows up in prose
   (`## Role` etc.); it is not what goes in `git_names` (see below).
2. Slug: `[a-z0-9-]` only, no capitals. If the answer contains anything else, say so
   and ask again; don't silently normalize it.
3. GitHub username.
4. Role: a short label (for the frontmatter `role:` field) and, if they want to add
   more, a sentence or two beyond it (the opening of the `## Role` section).
5. Scope: what they own day to day, which areas, which memory categories, where
   their default authority stops.
6. Working style: how should the agent write for and with them, tone, verbosity,
   language preference.
7. Machines: hostname or device name for the machine they're setting up on right
   now. More can be appended later, one per line.

Writes:

```bash
cp operators/operator_template.md operators/<slug>.md
```

Fill the copy's frontmatter: `slug` (answer 2), `git_names` (a single-item list
holding the exact `GIT_NAME` value from P1, never a retyped version of answer 1: it
has to match `git config user.name` on the byte, or the resolution rule in
`operators/CLAUDE.md` never matches this operator on this machine), `github`
(answer 3), `role` (the short label from answer 4). Fill `## Role` (answer 4 in
full), `## Scope` (answer 5), `## Working style` (answer 6), and `## Machines`
(answer 7, one bullet). Remove the `<!-- CUSTOMIZE ... -->` comment: its job was to
point here, and it has done it.

**Idempotence.** If `operators/<slug>.md` already exists with its frontmatter and
sections filled in (not the template's `<placeholder>` values), show the operator
its current contents and ask whether to update it or skip this phase.

Check the P3 box in `SETUP-STATE.md` once the file is written.

---

## P4: areas

List the shipped areas, find-based, never a glob (a fresh clone may have the three
shipped defaults, more if an earlier run already added one, or fewer if one was
already deleted):

```bash
find areas -mindepth 1 -maxdepth 1 -type d | sort
```

For each area the `find` prints, ask: keep, rename, or delete. Once every area
found is resolved, ask once more, "any area to add?", and repeat until the answer
is no.

- **Keep**: no write, move to the next area.
- **Rename**: ask for the new name, then
  ```bash
  git mv areas/<old> areas/<new>
  ```
  Retitle the first `#` heading in both `areas/<new>/CLAUDE.md` and
  `areas/<new>/Context.md` to match, and drop the "Rename or delete this area"
  banner line from the top of `Context.md`: it already served its purpose, the
  operator just took the offer it was pointing at.
- **Delete**: confirm once more, by name, before touching anything: "delete
  `areas/<name>` and everything in it? This skill can't undo it." On yes:
  ```bash
  git rm -r areas/<name>
  ```
- **Add**: ask for the new area's name and a one-line description of what lives
  there, then create `areas/<name>/CLAUDE.md` and `areas/<name>/Context.md`
  following the shape of the shipped areas: `CLAUDE.md` gets `# areas/<name>/` plus
  `## What lives here`, `## Conventions`, `## Live status` (pointing at `memory/`,
  same as every other area); `Context.md` gets a `#` title and section headers for
  the description given, with no "Rename or delete this area" banner, since the
  operator is creating this one on purpose, not inheriting it as a placeholder.

**Idempotence.** An area already renamed or deleted in an earlier run simply won't
appear in this run's `find` output, since the directory itself is gone or already
has its new name; there is nothing extra to check beyond running the `find` fresh
each time this phase starts.

Check the P4 box in `SETUP-STATE.md` once every area from the `find` output is
resolved and the final "any area to add?" got a no.

---

## P5: first projects

Ask for 2 to 3 active projects. For each one, one question at a time:

1. Name.
2. Status: one of the shipped scale, 🔴 urgent · 🟠 stalled/waiting · 🟡 active ·
   🟢 on track · 🔵 wrap-up (done, loose ends open) · ❌ closed.
3. Next action: the single next thing that needs to happen to move it forward.
4. Owner: a slug from the registry built so far (P3, plus P6 if this is a resumed
   run that already registered teammates). If the named owner isn't registered
   yet, default to the admin's own slug and say so out loud in chat; never default
   silently.
5. Deadline, if there is a hard date. Skip this question entirely if the operator
   already volunteered one while answering 1-3.

For each project, writes:

```bash
cp memory/project_template.md memory/project_<slug>.md
```

Fill the frontmatter to the frozen schema exactly: `name` (the full filename stem,
`project_<slug>`, not the bare slug: `memory/project_example.md` ships with `name:
project_example` as the precedent), `type: project`, `status` (answer 2's emoji),
`deadline` (answer 5, only if given: omit the line entirely rather than leaving it
blank), `owner` (answer 4). Fill `## Status` (current state, consistent with the
status emoji), `## Next action` (answer 3), and `## Context` (why the project exists, 2-4
sentences drawn from the conversation). Remove the `<!-- CUSTOMIZE ... -->`
comment. First `## Updates` line, dated with:

```bash
date +%Y-%m-%d
```

`- <that date>: Project created during setup.`

Add one line under `## Projects` in `memory/MEMORY.md`, in the shipped index
format: `- [<project title from answer 1>](project_<slug>.md) - <status emoji> <one
line> Next: <next action>`.

Once every project is written, ask: "delete the shipped example,
`memory/project_example.md`, and its index line?" On yes:

```bash
git rm memory/project_example.md
```

and remove its line from `## Projects` in `memory/MEMORY.md`. On no, leave both in
place; a later run of this phase, or the operator by hand, can offer again.

**Idempotence.** A project slug that already has a `memory/project_<slug>.md` file
with non-placeholder content is a project already created: show the operator its
current contents and ask whether to update it or skip, same as every other phase.
A `memory/project_example.md` that is already gone means a shorter question: skip
straight to confirming its index line is also gone, rather than re-asking about the
file.

Check the P5 box in `SETUP-STATE.md` once every project is written (or explicitly
skipped) and the example-deletion question has a final answer either way.

---

## P6: team registration

Register every teammate joining after the admin, one at a time. For each person,
ask, one question at a time:

1. Display name.
2. Slug: `[a-z0-9-]` only, no capitals. If the answer contains anything else, say so
   and ask again; don't silently normalize it. Also check it against every existing
   file in `operators/`: two operator files must never share a slug
   (`operators/CLAUDE.md`'s uniqueness constraint). If it collides, ask for a
   different one.
3. Their `git config user.name` value: ask the admin what it reads on this
   teammate's machine, or accept the admin's best guess if they don't know. Either
   way, tell the operator out loud that this is only a starting point: the teammate
   is the one who confirms or corrects it, in `operators/ONBOARDING.md` Step 4, once
   they're actually at their own keyboard.
4. GitHub username.
5. Role: a short label for the frontmatter `role:` field and, if the admin wants to
   add more, a sentence or two beyond it.

Writes, same shape as P3 (that phase has the full frontmatter and section-filling
detail; this one doesn't repeat it): `cp operators/operator_template.md
operators/<slug>.md`, then fill `slug` (answer 2), `git_names` (a single-item list
holding answer 3), `github` (answer 4), `role` (the short label from answer 5), and
`## Role` (answer 5 in full). Unlike P3, this interview doesn't ask Scope, Working
style, or Machines: the admin isn't always positioned to answer those on someone
else's behalf, so leave `## Scope`, `## Working style`, and `## Machines` exactly as
the template ships them, for the teammate to fill in themselves once they're
onboarded. Remove the `<!-- CUSTOMIZE ... -->` comment.

**Idempotence.** Same rule as P3: if `operators/<slug>.md` already exists with
non-placeholder content, show the operator its current contents and ask whether to
update it or skip this teammate.

Once a teammate's file is written, ask "any more teammates to register?" and repeat
until the answer is no.

Then, for every teammate just registered, the invitation. This is an outward-facing
action: list who is about to be invited and get the operator's ok before running the
block at all.

```bash
REPO_SLUG="$(git remote get-url origin | sed -E 's#^(git@github.com:|https://([^/@]+@)?github.com/)##; s#\.git$##')"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh api -X PUT "repos/$REPO_SLUG/collaborators/<github-username>" -f permission=push \
    && echo "INVITED <github-username>"
else
  echo "gh unavailable: invite by hand. Open https://github.com/$REPO_SLUG/settings/access"
  echo "-> Add people -> <github-username> -> role: Write."
fi
```

Run this once per teammate registered this run, substituting `<github-username>` for
their answer to question 4. Do not send them `operators/ONBOARDING.md` and their slug
yet, even once they're invited: their registry file only exists on this machine until
P7 pushes it, and it has to be on `main` before they can clone in
`operators/ONBOARDING.md` Step 3.

Check the P6 box in `SETUP-STATE.md` once every teammate for this run is registered
(the loop got a final "no more") and every invitation for this run has been sent or
attempted.

---

## P7: first push

Everything P2 through P6 wrote so far still needs to land on `main`. Stage by
allow-list only (never a bare `git add -A` or `git add .`): show the operator what
changed, then check for and stage exactly the files this setup created or edited,
file by file where the set is fixed and find-based where it varies:

```bash
git status
for f in "Company - Context.md" CLAUDE.md memory/MEMORY.md; do
  [ -f "$f" ] && git add -- "$f"
done
find operators -maxdepth 1 -name '*.md' \
  ! -name CLAUDE.md ! -name ONBOARDING.md ! -name operator_template.md \
  -exec git add -- {} +
find memory -maxdepth 1 -name 'project_*.md' ! -name project_template.md -exec git add -- {} +
git add -A -- areas
git diff --cached --stat
```

`git add -A -- areas` is the one path-scoped exception to the bare-tree ban: it's
scoped to the areas/ tree P4 reshaped, including the deletions a rename produces
(`git mv` alone leaves the old path staged as a delete and the new path untracked;
`-A` on that one folder picks up both sides). Because the scope is the whole tree
rather than a single folder, eyeball the `git diff --cached --stat` output below for
stray files under `areas/` before pushing. The ban on a bare `git add -A` or `git
add .` across the whole tree still stands everywhere else in this skill.

Show the operator the `git diff --cached --stat` output, then ask: "everything
staged becomes shared with every operator you invite; push now?" Only on yes:

```bash
git commit -m "chore: initial company setup"
git push origin main && echo "PUSHED" || echo "PUSH FAILED: run /sync, then rerun this phase."
```

On `PUSH FAILED`, do not retry blindly and never force: run `/sync` to resolve
whatever the remote has that this clone doesn't, then rerun P7. The rerun is
idempotent: the allow-list staging above only ever adds what's actually changed, so
if the local tree is already clean and sits ahead of `origin/main` (everything from
this run already committed, just not yet pushed), the staging block stages nothing
new and this phase can skip straight to the `git push` line.

Check the P7 box in `SETUP-STATE.md` once `PUSHED` prints.

---

## P8: smoke test and wrap-up

Mirror `SETUP.md` Step 10, now that P7 has put everything on `main`:

```bash
BRAIN="$(pwd)"
CC_PROJECT="$HOME/.claude/projects/$(echo "$BRAIN" | sed 's/[^A-Za-z0-9-]/-/g')"
ls -l "$CC_PROJECT/memory"
```

Confirm the arrow in that listing still points into this repo's `memory/` folder.

If it doesn't, either an outright missing path or the `memory-symlink=missing` WARN
P1 already gave, this is where it gets resolved: P1 let you continue without it
because setup could still proceed with everything else; P8 is the last stop before
calling setup done, and every operator onboarded after this point inherits whatever
is broken here. Fix it now, with the identical block from `SETUP.md` Step 5:

```bash
BRAIN="$(pwd)"
CC_PROJECT="$HOME/.claude/projects/$(echo "$BRAIN" | sed 's/[^A-Za-z0-9-]/-/g')"
mkdir -p "$CC_PROJECT"
[ -e "$CC_PROJECT/memory" ] && mv "$CC_PROJECT/memory" "$CC_PROJECT/memory.local-backup"
ln -s "$BRAIN/memory" "$CC_PROJECT/memory"
ls -l "$CC_PROJECT/memory"
```

Confirm the arrow again before moving on.

Then, in chat rather than a command, ask the operator to type `/` and confirm the
skills suite lists. If that check fails too, fix it now, same rule: before calling
setup done. Once both pass, suggest `/sync` as the first real command to run, since
it's the safe way to confirm this machine can still reach the shared repo right
after the push.

Once both checks pass, delete the state file, the last write this skill makes:

```bash
rm -f SETUP-STATE.md
```

Open the tour:

```bash
FILE="WELCOME.md"
( open "$FILE" 2>/dev/null || xdg-open "$FILE" 2>/dev/null || start "" "$FILE" 2>/dev/null ) \
  || echo "Open this file in your browser: $FILE"
```

Confirm the path to the operator in chat, whether or not a browser actually opened.

Closing message: hand `operators/ONBOARDING.md` and each teammate's slug to them
now, the point P6 deferred it to. Their registry file is on `main` as of P7; they can
clone.

## Self-improvement

At the end of the run, check it against these friction triggers: **avoidable
round-trip · improvisation · breakage · token waste · operator correction**
(full definitions in `skills/_improvements/capture.md`). If at least one fired,
ask the operator "there was friction on X, should I log it?"; on their ok,
append an entry to `skills/_improvements/friction-log.md` in the format
`capture.md` defines. Clean run: say nothing. Never self-edit this skill;
improvements go through `/skill-improve`.
