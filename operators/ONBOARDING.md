# Onboarding a new operator

This is the path for the second (and every later) operator joining an
existing company brain. The first operator's setup lives in `SETUP.md` at
the repo root; this file is for everyone who joins after that.

Every command below runs **on your own machine**. Nothing here is
copy-pasted from someone else's terminal output: values like your workspace
path are computed fresh, locally, at each step.

---

## Step 1: Install git and Claude Code

If you don't already have them, install `git` and Claude Code before
continuing.

---

## Step 2: Authenticate with GitHub and accept the invite

```bash
gh auth login
```

Accept the collaborator invite the admin sent you (check your email or the
notification from GitHub).

---

## Step 3: Clone the company repo

```bash
git clone <company-repo-url>
cd <repo-folder>
```

---

## Step 4: Set your git identity

Your admin already created `operators/<your-slug>.md` for you and told you your slug.
Verify it:

```bash
cat operators/<your-slug>.md
```

If the file is missing, or its `git_names` entry doesn't match what
`git config user.name` will read on this machine, ask your admin to fix it. Don't
create or edit the file yourself: `operators/` is admin-managed (see
`operators/CLAUDE.md`).

Once the file is right, set your identity to match it exactly:

```bash
git config user.name "<exact value from git_names>"
git config user.email "<your email>"
```

This matters beyond convention: the resolution rule in `operators/CLAUDE.md`
matches `git config user.name` against every registry file's `git_names` to
figure out who you are. If it doesn't match exactly, nothing else in this
repo can resolve your identity.

---

## Step 5: Link the memory folder

Claude Code auto-loads memory from a per-project folder under `~/.claude`.
Point it at this repo's `memory/` folder with a symlink, computed on your
own machine:

```bash
BRAIN="$(pwd)"
CC_PROJECT="$HOME/.claude/projects/$(echo "$BRAIN" | sed 's/[^A-Za-z0-9-]/-/g')"
mkdir -p "$CC_PROJECT"
[ -e "$CC_PROJECT/memory" ] && mv "$CC_PROJECT/memory" "$CC_PROJECT/memory.local-backup"
ln -s "$BRAIN/memory" "$CC_PROJECT/memory"
ls -l "$CC_PROJECT/memory"
```

Check that last line: you should see the arrow pointing into your repo's `memory/`
folder. If it doesn't, stop and fix it before continuing; nothing downstream works off
a broken symlink.

On Windows, use a junction from `cmd` in the repo folder instead:

```
mklink /J "%USERPROFILE%\.claude\projects\<workspace-path-with-dashes>\memory" memory
```

---

## Step 6: Register skills

Claude Code discovers project skills in `.claude/skills/`, while this repo
keeps them versioned in `skills/`. Link the two once:

```bash
mkdir -p .claude && ln -s ../skills .claude/skills
```

On Windows, create a junction instead, from `cmd` in the repo folder:
`mklink /J .claude\skills skills`.

`.claude/` is gitignored, so this link stays local to your machine.

If your team adopted `docs/GOVERNANCE.md` step 3 (there are active lines in
`.github/sensitive-paths.txt`), activate the local guard on this clone too:

```bash
git config core.hooksPath githooks
```

It is a per-clone setting, so every new clone repeats it; `/system-checkup` reminds
you when it is missing.

---

## Step 7: Optional MCP connectors

If your team uses MCP connectors (calendar, email, project tools), set them
up now. This is optional and depends on what your team has configured; ask
whoever onboarded before you what they're running.

---

## Step 8: Smoke test

Open the repo in Claude Code and run:

```
/sync
```

to confirm you're up to date with the shared repo, then:

```
/daily-briefing
```

to confirm memory loaded correctly and the briefing can see the current
state. If either fails, see Troubleshooting below before going further.

---

## Step 9: Read WELCOME.md

`WELCOME.md` is the content-first walkthrough: what this brain is for, how
the daily loop works, and where to look next. Read it once you're through
the plumbing above.

---

## Troubleshooting

### The symlink already exists

Step 5 checks for an existing `memory` folder at the target path and backs
it up to `memory.local-backup` before linking. If you already ran onboarding
once and are re-running it, delete or inspect that backup first:

```bash
ls "$HOME/.claude/projects/$(pwd | sed 's/[^A-Za-z0-9-]/-/g')/"
```

If the symlink is already pointing at this repo's `memory/`, you're done;
skip the step.

### Your identity doesn't resolve

If `/sync` or `/daily-briefing` complains that your operator can't be
resolved, check that `git config user.name` prints exactly one of the
`git_names` entries in exactly one file under `operators/`:

```bash
git config user.name
grep -rl "$(git config user.name)" operators/
```

Zero results: your `git_names` entry isn't registered yet; ask your admin to add it
(see Step 4). More than one result: two operator files claim the same `git_names`
entry, which is a registry bug, fix it (see `operators/CLAUDE.md`'s uniqueness
constraints).

### Skills aren't discovered

Confirm the symlink from Step 6 actually resolves:

```bash
ls -la .claude/skills
```

If it's missing or broken, re-run Step 6. If it resolves but a specific
skill still isn't triggering, check that its folder has a `SKILL.md` at the
top level (`skills/<name>/SKILL.md`).
