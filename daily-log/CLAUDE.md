# daily-log/

Per-operator, per-day session record.

## Convention

- One file per operator per day: `YYYY-MM-DD-<slug>.md`. ISO date, then the
  operator's registry slug.
- The slug always comes from `operators/`, resolved via the rule in
  `operators/CLAUDE.md`. Never derive it from `git config user.name`
  directly: a name is free text, a slug is a value a registry file claims.
  If the operator can't be resolved, fix that first (see
  `operators/ONBOARDING.md` Troubleshooting) rather than guessing a
  filename.
- Sections, in order:
  - `## What happened`: what was worked on, in plain terms.
  - `## Decisions`: anything decided during the session, and why.
  - `## Open threads`: unfinished business to pick up next session.

## What this is not

A daily log is a session record, not a project tracker. Status, next
actions, deadlines, and ownership live in `memory/` (see `memory/CLAUDE.md`).
If something in a log entry needs to be findable later or acted on across
sessions, it belongs in a memory file too, the log is where it happened,
memory is where it stands.

## Rules

- Never edit another operator's log file. If a session touches someone
  else's work, note it in your own log and let them pick it up in theirs.
- Don't backfill or edit a past day's log to reflect information learned
  later. Add a new entry on today's date instead.
