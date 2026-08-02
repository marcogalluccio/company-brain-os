# AGENTS.md

This workspace is built Claude Code-first: skills, an auto-loaded `CLAUDE.md`, guided
flows. If you are using a different agent (Cursor, Codex, Copilot, or another tool), or
working by hand, start with `CLAUDE.md`. It is the constitution every convention in this
repo follows, regardless of which agent is reading it.

## Honest framing

Outside Claude Code, you keep the brain: the markdown conventions, `memory/`,
`daily-log/`, and the git flow, none of which depend on any particular tool. You lose
the operating system: skills, auto-load, and guided flows are what Claude Code adds on
top of the brain. Every skill-driven flow below has a manual equivalent: more typing,
same underlying structure.

| Skill-driven flow | Manual equivalent |
| --- | --- |
| `/sync` | `git pull`, then read your teammates' recent daily logs for what changed. |
| `/session-debrief` | Write today's entry in `daily-log/YYYY-MM-DD-<your-slug>.md`, update the relevant files in `memory/` (including `MEMORY.md`'s index line), then commit and push. |
| `/daily-briefing` | Read `MEMORY.md`, then the last few days of daily logs, to build your own priority list before starting work. |

Everything else, resolving the active operator, naming a new area, filing something in
`memory/`, follows the same rules whether a skill runs it or you do it by hand: read the
relevant `CLAUDE.md` (root, `memory/`, `operators/`, `daily-log/`, or the area you are
touching) before acting.

None of this requires Claude Code. It requires reading the `CLAUDE.md` files and
following the same conventions yourself.
