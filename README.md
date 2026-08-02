# Company Brain OS

A shared company brain for small teams, powered by Claude Code and GitHub.

A private repo becomes your team's operational memory: what's active, what happened,
who owns it, readable cold by any operator or agent that opens the repo. No app to
host, no database to run. Git is the sync layer, markdown is the format, Claude Code
is the interface.

## Who it's for

Small teams, 2 to 5 operators, who want a shared operational memory that survives
turnover instead of living in one person's head, one person's notes app, or one
person's chat history. Beyond 5 operators, the shared-context model needs
partitioning, which is out of scope for v1.0.0 and on the roadmap.

Working alone? The multi-operator scaffolding here (an `operators/` registry,
per-operator daily logs, an offboarding checklist) is overhead you don't need. Use the
solo sibling instead: [big-brain-os](https://github.com/marcogalluccio/big-brain-os).

## What you get

- **Memory that survives anyone leaving.** A flat index (`memory/MEMORY.md`) plus one
  file per active project, reference, or lesson learned, so an agent or a new operator
  can read the current state cold, no handover meeting required.
- **Per-operator daily logs.** `daily-log/YYYY-MM-DD-<slug>.md`, one file per person per
  day, so parallel sessions never collide in one shared file.
- **A daily git cycle.** Sync at the start of a session, work, debrief at the close: log
  what happened, update memory, commit, push. Work lands on `main` every session by
  default; branch protection and review gates are opt-in, never required.
- **A 15-skill suite.** Guided Claude Code flows that turn the loop above, and the
  handful of things every operator does repeatedly, into commands instead of
  remembered process. See the matrix below.

## The skills suite

The matrix below describes the 15 skills this template ships with. Every skill is
optional: the core loop (sync, work, debrief) is markdown and git, and works whether
or not you ever install one.

| Skill | Pack | Works on |
| --- | --- | --- |
| `/setup-company-brain` | Life cycle | Any setup |
| `/sync` | Life cycle | Any setup |
| `/daily-briefing` | Life cycle | Any setup |
| `/session-debrief` | Life cycle | Any setup |
| `/html-preview` | Life cycle | Any setup |
| `/memory-checkup` | Life cycle | Any setup |
| `/skill-improve` | Life cycle | Any setup |
| `/eod-review` | Life cycle | Any setup |
| `/pr-review` | Governance | Inert until `docs/GOVERNANCE.md` is adopted |
| `/ship` | Governance | Inert until `docs/GOVERNANCE.md` is adopted |
| `/system-checkup` | Governance | Partially useful without it: the memory and structure checks run on any setup, the git-layer checks need it |
| `/skill-detector` | Extras | Any setup |
| `/handover` | Extras | Any setup |
| `/meeting-debrief` | Extras | Any setup, transcript-first; an MCP connector for a meeting-notes tool is an optional extra for auto-fetch |
| `/sparring` | Extras | Any setup |

Eight life cycle skills work on any setup, no matter how small the team. Three
governance skills only do something once you adopt `docs/GOVERNANCE.md`; until then
they are dead weight sitting in `skills/`. Four extras round out the suite.

### Dependencies

| Tool | Needed by |
| --- | --- |
| git | Everything. The only hard requirement. |
| `gh` CLI | The governance pack (`/pr-review`, `/ship`, and the git-layer checks in `/system-checkup`). |
| Python 3 | Only if you adopt the advanced memory layer (`docs/ADVANCED.md`); the core loop needs none of it. |
| MCP connectors (optional) | `/meeting-debrief`'s auto-fetch path. Everything else needs none. |

## Quickstart

1. On GitHub, click **Use this template → Create a new repository**. Set visibility
   to **Private**: your company's memory, daily logs, and client notes are going to
   live here.
2. Follow `SETUP.md`. It walks the first operator through cloning, git identity,
   linking skills and memory, filling in company context, and inviting the rest of
   the team.
3. Every operator after the first follows `operators/ONBOARDING.md` instead.

Not using Claude Code? `AGENTS.md` covers what changes: you keep the brain, you lose
the guided flows, and it maps each one to its manual equivalent.

## Growth

The core loop above is the whole workspace. Nothing else is required. Two independent
growth paths sit on top of it, and you can adopt either, both, or neither:

- `docs/GOVERNANCE.md`: a heavier git layer, branch protection, feature branches plus
  `/ship`, CODEOWNERS, for when the direct-push default needs guardrails.
- `docs/ADVANCED.md`: a heavier memory layer, salience scoring, a machine-generated
  index, for when `memory/MEMORY.md` outgrows a flat list. Ships with v1.0.0.

## Siblings

- [big-brain-os](https://github.com/marcogalluccio/big-brain-os): the solo version.
  One operator, no registry, no per-operator logs.

## License

MIT, see `LICENSE`. Created by Marco Galluccio.
