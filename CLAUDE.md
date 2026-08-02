# CLAUDE.md

Operational brain of {{COMPANY_NAME}}.

This repo is the source of truth. Every operator works from their own local clone;
nothing is "somebody's local truth" once it lands on `main`. Daily work lands directly
on `main` through the session debrief.

This file is the constitution: the rules every skill, every agent, and every operator
follows. Read `Company - Context.md` for who this company is and what it does.

## Operators

The full registry lives in `operators/`, one file per operator.

> Resolve the active operator by matching `git config user.name` against
> every registry file's `git_names`. Exactly one match: proceed. Zero or
> multiple matches: stop and tell the user how to fix their identity or the
> registry. Never guess, never derive a slug from the name itself.

Adding someone? Point them at `operators/ONBOARDING.md`.

## Boot sequence

Auto-loaded by Claude Code on session start (no action needed):
- This file (`CLAUDE.md`)
- The memory index `MEMORY.md` (see Memory system, below)

On every new conversation, before starting any task:
1. Read the most recent daily logs: your own and your teammates', so you catch up on
   unfinished threads before starting new work.
2. Read today's daily log, if it exists.
3. Read the `CLAUDE.md` of whatever area the task touches (`areas/<name>/CLAUDE.md`).

## Structure

- `operators/`: the registry of who runs this brain, and how to resolve who is running
  the current session.
- `areas/`: the work itself, one subfolder per area (clients, operations, content by
  default; rename, delete, or add your own).
- `daily-log/`: per-operator, per-day session records.
- `memory/`: live project state, what is active, what is next, who owns it.
- `private/`: gitignored; raw client materials, secrets, anything that must not sync.
- `skills/`: Claude Code skills, if you adopt them; `_improvements/` captures friction
  against the skill layer itself.
- `docs/`: the growth docs, `ADVANCED.md` and `GOVERNANCE.md`.
- `scripts/`: optional tooling, used only if you adopt `docs/ADVANCED.md`.
- `.claudeignore`: paths Claude Code never reads into context, even on request
  (currently just `private/`).

## Memory system

Memory lives in `memory/`, indexed by `MEMORY.md`: one line per item, emoji status, a
pointer to the file that holds full context. Four categories:
- **Project**: active work with a status and a next action.
- **Strategic**: long-term positioning and directions.
- **Feedback**: lessons learned and agent-behavior rules.
- **Reference**: pointers to external resources.

Status scale: 🔴 urgent · 🟠 stalled/waiting · 🟡 active · 🟢 on track ·
🔵 wrap-up (done, loose ends open) · ❌ closed.

`MEMORY.md` is the dashboard, auto-loaded every session. Closed items are archived,
never deleted: status `❌`, file moved to `memory/archive/`. The operating rules of the
layer (index format, preserve-first, anti-patterns) live in `memory/CLAUDE.md`, read it
before writing anything to memory.

## The daily git cycle

Work happens directly on `main`. `/sync` at the start of a session pulls the shared
state, you work, `/session-debrief` at the close writes today's log, updates memory,
commits, and pushes.

Iron rules:
- Never force-push.
- Never skip hooks (`--no-verify`).
- If the debrief hits a conflict, it stops and asks. It never resolves silently.
- Resolve inside the rebase (a targeted `add` plus `continue`) or abort to a safe,
  explicit deferral. Never abort onto a dirty tree: an abort there can destroy another
  operator's in-progress work.
- Index collisions between two debriefs (both touched `memory/MEMORY.md`): see
  `memory/CLAUDE.md`'s "When two debriefs collide".

## What never enters the brain

Some things must never be written into this repo, not even by accident:
- Secrets: API keys, tokens, passwords, `.env` files, credentials.
- Raw client materials under NDA.
- Regulated personal data.

These go in `private/` (gitignored, stays on the machine that created them) or outside
the repo entirely. If you are unsure whether something qualifies, treat it as private
until you are sure it does not.

## Rules

- Never modify a `CLAUDE.md` file without the operator's explicit approval first. These
  files decide how every agent in the system behaves.
- Never push to the shared repo or deploy anything without explicit permission. Carve-out:
  invoking `/session-debrief` pre-authorizes that skill's own commit-and-push to `main`.
  Everything else, new remotes, deploys, force operations, still needs explicit
  permission.
- Structure changes (CLAUDE.md, memory schema, skills) are co-created: propose options
  in chat and let the operator confirm before writing the final version.
- Memory changes are propose-then-write: show what you intend to add or change before
  you write it.

## Growth

This constitution covers the Core layer: the smallest workspace that works. Two
independent scales sit on top of it, and you can adopt either without the other:

- `docs/ADVANCED.md`: a heavier memory layer (salience scoring, a machine-generated
  index) for when `memory/` outgrows a flat file list.
- `docs/GOVERNANCE.md`: a heavier git layer (branch protection, feature branches,
  CODEOWNERS) for when the daily direct-push flow needs guardrails.
