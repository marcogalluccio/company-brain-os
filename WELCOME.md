# Welcome

Setup is done. This is the short tour: what to run first, where things live, where to
grow next.

## Try these in order

1. `/sync`: pull the shared state, see if anything changed since your last session.
2. Open `memory/MEMORY.md`: the dashboard, every active project, one line each.
3. `/daily-briefing`: turns that dashboard into a priority list for today.
4. Work. Whatever the briefing turned up, or whatever you came here to do.
5. `/session-debrief`: closes the loop, logs today in `daily-log/`, updates the
   memory files that changed, commits, pushes.

Sync, brief, work, debrief. That's the whole day-to-day rhythm; everything else in this
repo supports it.

## Where things live

- `operators/`: who runs this brain, and how a session resolves who you are.
- `areas/`: the work itself, one folder per area of the company.
- `daily-log/`: what happened, per operator, per day.
- `memory/`: what's active, what's next, who owns it.
- `private/`: gitignored, raw materials that must never sync.
- `skills/`: the guided flows above, plus anything your team adds.
- `docs/`: the two growth docs, read them once the core loop stops being enough.
- `scripts/`: optional tooling for the heavier memory layer (`docs/ADVANCED.md`), if
  you adopt it.

## When you're ready for more

Two docs cover the growth paths, and you can adopt either independently of the other:

- `docs/ADVANCED.md`: a heavier memory layer, for when `memory/` outgrows a flat list.
- `docs/GOVERNANCE.md`: a heavier git layer, for when direct pushes to `main` need
  guardrails.

Neither is required. The core loop above works fully without them.

## Stuck?

Open an issue on the repo. That's the whole support channel.
