# Setup

Company Brain OS turns this template into your company's operational second brain: a
private repo, one folder per operator, and a memory layer that any of you, or your
agent, can read cold. This file is the manual path, step by step.

Two other files round this out:
- `WELCOME.md`: the short tour once setup is done.
- `AGENTS.md`: what changes if you don't use Claude Code (see Part C below).

---

## Part A: the first operator (admin)

Do this once, when the company brain does not exist yet.

### Step 1: Use this template

On GitHub, open the Company Brain OS template repository
(`https://github.com/marcogalluccio/company-brain-os`) and click the green
**Use this template** button, top right, then **Create a new repository**.

Name it whatever fits your company, and set visibility to **Private**. Your company's
data, memory, daily logs, client notes, is going to live in this repo, so it should
never be public. The Private toggle sits on the same "Create a new repository" page,
just below the repository name field.

### Step 2: Clone your repo

Clone the repo you just created, not the template:

```bash
git clone <your-new-repo-url>
cd <repo-folder>
```

Then check you actually cloned the right thing:

```bash
git remote get-url origin
```

The output must **not** contain `marcogalluccio/company-brain-os`. If it does, you
cloned the template itself instead of your own copy. Delete the folder and start over
from Step 1.

### Step 3: Set your git identity

```bash
git config user.name "Your Name"
git config user.email "you@company.com"
```

Whatever you put in `user.name` here is the value you register as a `git_names` entry
for yourself in Step 6. The resolution rule in `operators/CLAUDE.md` matches this value
against the registry to figure out who is running a session, so it has to match
exactly.

### Step 4: Register skills

Claude Code discovers project skills in `.claude/skills/`, while this repo
keeps them versioned in `skills/`. Link the two once:

```bash
mkdir -p .claude && ln -s ../skills .claude/skills
```

On Windows, create a junction instead, from `cmd` in the repo folder:
`mklink /J .claude\skills skills`.

`.claude/` is gitignored, so this link stays local to your machine.

### Step 5: Link the memory folder

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

### Step 6: Fill in your company's context

Three things need real content before this brain is useful:

- `operators/<your-slug>.md`: copy `operators/operator_template.md`, fill in the
  frontmatter (your `git_names` entry has to match Step 3 exactly) and the sections
  below it. This is the only operator file you create for yourself; you register every
  operator after you in Step 8.
- `Company - Context.md`: what the company does, how it makes money, who is here, what
  tools it runs on day to day, and any house conventions the brain should respect. Its
  title and one-liner are placeholder tokens (`{{COMPANY_NAME}}`,
  `{{COMPANY_ONE_LINER}}`); replace both with your real content.
- Root `CLAUDE.md` also carries `{{COMPANY_NAME}}`, on its first line ("Operational
  brain of {{COMPANY_NAME}}."). Open the file and replace that token by hand.

Fill these by hand, or run `/setup-company-brain` if you're on Claude Code (ships with
the skills suite) and want the agent to walk you through it one question at a time.

### Step 7: Shape your areas

The template ships with three example areas under `areas/`: `clients`, `content`,
`operations`. Rename, delete, or add to them until they match how your company
actually splits its work. Each area folder keeps a `CLAUDE.md` (conventions and scope)
and a `Context.md` (content to fill in); edit both when you rename or add one.

The template also ships one example memory file, `memory/project_example.md`. Delete
it once you have a real project to replace it with, and remove its index line from
`memory/MEMORY.md` by hand: deleting the file doesn't clean up the dashboard line that
points at it.

### Step 8: Register and invite your operators

You create every other operator's registry file, not them. For each person joining:

1. Copy `operators/operator_template.md` to `operators/<their-slug>.md`. Fill in their
   slug, their `git_names` (ask what `git config user.name` reads on their machine, or
   enter your best guess; they confirm or correct it in `operators/ONBOARDING.md`
   Step 4), their GitHub username, and their role.
2. Commit and push the file: `git add operators/<their-slug>.md && git commit -m
   "chore: register <their-slug>" && git push`. It has to be on `main` before they
   clone in `operators/ONBOARDING.md` Step 3, or their own file won't be there yet.
3. On GitHub, add them as a collaborator on the repo (repo Settings → Collaborators).
   They need this before `operators/ONBOARDING.md` Step 2 can accept their invite.
4. Send them `operators/ONBOARDING.md` and their slug.

### Step 9: First push

Everything else you've filled in so far (`Company - Context.md`, root `CLAUDE.md`,
your areas) still needs to land on `main`. Look before you commit: everything staged
here becomes shared with every operator you invite.

```bash
git status
git add -A && git commit -m "chore: initial company setup" && git push
```

### Step 10: Smoke test

Confirm the plumbing actually works before you call setup done:

- `ls -l "$CC_PROJECT/memory"` (the same check from Step 5): the symlink still
  resolves into this repo's `memory/`.
- Open the repo in Claude Code. Confirm the skills appear (typing `/` should list
  them), then run `/sync` to confirm it can reach the shared repo.

If any of this fails, fix it now. Every operator you onboard after this point inherits
whatever is broken here.

---

## Part B: every operator after the first

If you're joining a company brain someone else already set up, you don't need this
file. Follow `operators/ONBOARDING.md` instead: it's the complete path for every
operator after the admin.

---

## Part C: if you don't use Claude Code

Everything above assumes Claude Code: skills, an auto-loaded `CLAUDE.md`, and the
`/sync`, `/daily-briefing`, `/session-debrief` flows. None of that is required. Read
`AGENTS.md` for the honest version of what changes: outside Claude Code you keep the
brain (the markdown conventions, `memory/`, `daily-log/`, the git flow), you lose the
operating system (skills, auto-load, guided flows) that Claude Code adds on top of it.
`AGENTS.md` has a table mapping each skill-driven flow to its manual equivalent; use
that table once your repo exists instead of the steps above, since the plumbing in
Part A (symlinks, skill registration) is Claude Code-specific and doesn't apply to you.
