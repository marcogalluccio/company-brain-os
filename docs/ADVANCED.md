# Advanced memory: salience and the machine index

An opt-in layer on top of the core memory system in `memory/CLAUDE.md`. Nothing
here changes what the core schema means; it only adds fields and tooling on top
of it, and every part of it can be removed without touching the core.

## 1. What this is and when to adopt it

The core memory layer, a flat `MEMORY.md` plus one file per item, is enough for
most teams for a long time. You read the index, you read the files it points
at, you keep it current by hand. That works as long as the active corpus is
small enough to eyeball.

Adopt this layer when it stops being small enough. The rough signal: 25 to 30 or
more active files, or the daily briefing keeps surfacing the wrong priorities
because nothing in the index says which items actually matter right now versus
which ones are just old. Below that size, skip this doc entirely: it adds
maintenance for a problem you don't have yet.

This layer is independent of `docs/GOVERNANCE.md`. You can adopt one, both, or
neither; they don't interact. It is also the only place in the template that
requires Python 3: the core layer needs nothing beyond git, bash and a text editor,
this one needs the scripts in `scripts/` (each ships with its tests under
`scripts/tests/`; `bash scripts/tests/run-all.sh` runs them all).

## 2. Frontmatter extensions (opt-in, additive)

Three fields, added to the frontmatter of `project_*` and `strategic_*` files
only. `reference_*` and `feedback_*` files are exempt by type: they don't carry
a `status` in the core schema either, and salience is meaningless for material
that doesn't have a state to track.

```yaml
last_touched: YYYY-MM-DD   # date of the last real work on this item, refreshed by the debrief
salience: 0.0               # computed, one decimal, never hand-tuned by feel
pinned: true                 # optional; manual override, omit when not pinned
```

`last_touched` and `salience` extend the core schema from `memory/CLAUDE.md`:
they sit alongside `name`, `type`, `status`, `deadline`, and `owner`, they don't
replace or redefine any of them. `pinned` is optional and only meaningful when
`true`; omit it rather than writing `pinned: false`.

## 3. The salience formula

```
salience = clamp01(recency + deadline_proximity + status_weight + pinned - decay)
```

`clamp01` means the result is bounded to `[0.0, 1.0]` after summing the terms.
The result is always rounded to one decimal. Every term comes from an
observable signal on the file itself, never from model judgment: the same
corpus, run through the same formula, must produce the same numbers every
time, at zero cost, whether a human or a script does the arithmetic.

| Term | Source | Rule |
|---|---|---|
| `recency` | `last_touched` | less than 7 days ago: +0.30. Less than 14 days: +0.20. Less than 30 days: +0.10. Otherwise: 0. |
| `deadline_proximity` | `deadline` | less than 7 days away, or up to 7 days past due: +0.40. Less than 30 days away: +0.25. Less than 90 days away: +0.10. No deadline, a deadline far in the future, or one more than 7 days past due: 0. |
| `status_weight` | `status` | 🔴 0.30 · 🟡 0.25 · 🟢 0.20 · 🟠 0.15 · 🔵 0.05 · ❌ 0. |
| `pinned` | `pinned` | `true`: +0.40. Absent or `false`: 0. |
| `decay` | `last_touched` | subtract 0.10 for every 30 days since the last touch (this term is subtracted, every other term is added). |

`recency` and `decay` are the same lever pointed in opposite directions: both
read `last_touched`, one rewards a recent touch and the other penalizes an old
one. That's deliberate. Time since the item was last worked on dominates the
score by design; nothing decays a stalled item except time passing without a
touch, and nothing keeps a fresh item's score up except touching it again.

The score lives only in frontmatter. It is never written into `MEMORY.md`. The
index is always in context, loaded on every session start; a number that ages
by 0.10 every 30 days has no business sitting in the one file that's read
constantly and rarely rewritten. Frontmatter is read on demand, which is where
a number with a shelf life belongs.

## 4. Who computes it, when

Three moments compute or read this score, and they map directly onto the
advanced-layer hooks already written into the skills that adopt this doc. All
three take their numbers from `python3 scripts/salience_sweep.py`, a read-only
script that applies the formula above to every project and strategic file in
every memory root and prints the result as JSON (`scores` for every file,
`restamps` where the written value drifted, `emoji_suggestions` for items that
have gone cold, `errors` for unparseable dates). Without Python the hooks fall
back to the formula by hand; the numbers are the same.

- **`/session-debrief`** refreshes `last_touched` and recomputes `salience` for
  the files the session actually touched, and only those files. The recompute
  is drafted and shown to the operator like any other memory write, gated
  behind the same approval as the rest of the debrief; it is never applied
  silently.
- **`/memory-checkup`** sweeps the whole corpus, not just what one session
  touched, and proposes restamps where the written `salience` has drifted from
  the recomputed value. This is the step that lets dormant items cool down:
  nothing in the debrief path touches a file nobody worked on, so without the
  sweep a stalled item's score would freeze at whatever it was the last time
  someone touched it. This check is read-only; it lists drift and proposes
  fixes, and writes nothing until approved.
- **`/daily-briefing`** recomputes salience live, read-only, across every
  project file, to rank a "Top 5 now" list at the top of the briefing. It
  writes nothing back to the files: this is a read for the briefing's own use,
  not a source of truth update.

If a team hasn't adopted this layer, none of the three fields exist in the
frontmatter, and all three hooks skip themselves silently: no mention of
salience appears anywhere in their output.

## 5. The machine index

`memory/INDEX.generated.md` is a machine-readable index of the memory corpus,
built by:

```bash
python3 scripts/build_index.py --write
```

and checked for drift with:

```bash
python3 scripts/build_index.py --check
```

It is deterministic: the same source files always produce identical bytes,
because the header carries a content hash of the sources rather than a
timestamp. `MEMORY.md` stays the human dashboard, read on every session start;
`INDEX.generated.md` is read on demand by tooling or by an agent that needs a
machine-parseable view of the corpus, never auto-loaded.

With federated roots (section 8) there is one generated index per root,
`areas/<name>/memory/INDEX.generated.md` next to each area's `MEMORY.md`;
`--write` regenerates all of them and `--check` names each stale one.

The file is gitignored (see the `memory/INDEX.generated.md` line in
`.gitignore`) and regenerated per machine. It is never committed and never
merged: a generated file with content-addressed output would still produce an
unresolvable conflict the moment two machines regenerate it at slightly
different times, so it simply never enters git. If you need it, run
`--write` locally; if a shipped skill needs to confirm it is current, it runs
`--check` and regenerates rather than trusting a copy anyone else produced.

## 6. The health gate

```bash
python3 scripts/memory_gate.py
```

is a read-only health check over `memory/`. It never writes to the files it
watches; it prints JSON findings to stdout. Useful flags: `--repo` to point at
a different tree, `--as-of` to evaluate deadlines as of a specific date instead
of today, `--only` to run a comma-separated subset of checks, `--baseline` to
diff findings against a previously saved JSON run, and `--strict` to turn
blocking findings into a nonzero exit code. `MEMORY_GATE_AREA_LIMIT_BYTES`
sets the cap of area indexes (default: the same cap as `MEMORY.md`).

The checks: `BROKEN` (a `[[wikilink]]` that doesn't resolve to a real file),
`ORPHAN` (a project or strategic node with zero incoming links), `ISLAND` (a
cluster of two or more nodes disconnected from the main body of the graph),
`INDEX-ROW` (a mismatch between a file and its index row, wherever the row lives:
`MEMORY.md`, `REFERENCES.md`, or `archive/INDEX.md`), `BUDGET`
(`MEMORY.md` approaching or over its auto-load size limit), `ROW-BUDGET` (rows of
`MEMORY.md` heavier than the per-row budget derived from that limit: one aggregated
warning naming the heaviest rows, the number the debrief reads before it writes),
`STALE-INDEX`
(`INDEX.generated.md` out of date with its sources), `DUP-STEM` (two files
sharing the same filename stem across active memory and the archive),
`DUP-ROOT` (the same stem in two memory roots: an item has one home, section
8), and `UNTYPED` (a file missing a valid `type` in its frontmatter).

Not every finding blocks. Only `BROKEN`, `DUP-STEM`, `DUP-ROOT`, a missing
`MEMORY.md` under `INDEX-ROW`, and `BUDGET` over the hard limit are blocking; the rest
(`ORPHAN`, `ISLAND`, the softer `INDEX-ROW` and `BUDGET` cases, `ROW-BUDGET`, `STALE-INDEX`,
`UNTYPED`) are warnings or informational. `--strict` only fails the exit code
on blocking findings; warnings alone never fail it. The JSON output's `green`
field is `false` whenever any finding exists at all, blocking or not, so
`green: false` with only warnings on it is expected and does not mean
`--strict` will fail.

On a small or young corpus, `ORPHAN` warnings on projects with no incoming
`[[wikilink]]`s are expected and benign: a new item hasn't been referenced from
anywhere yet, and that's normal, not a defect. As the corpus grows, link
related items to each other so the graph fills in; for the ones that are
genuinely meant to stand alone, allowlist them rather than chasing an
artificial link.

Accepted findings go in `memory/memory-gate-allowlist.yml`, one entry per
accepted finding:

```yaml
- check: ORPHAN
  target: project_example.md
```

Blocking findings can never be allowlisted. If an allowlist entry matches a
finding that is blocking, the match is rejected: the finding stays in the
output and the entry itself is reported back under `invalid_allowlist` instead
of silencing anything. The allowlist can only ever soften a warning or an
informational finding, never a block.

Run the gate weekly alongside `/memory-checkup`, or wire `--strict` into CI or
a pre-push hook if you want it enforced automatically; either way it stays
read-only and never rewrites memory on its own.

The `BUDGET` and `ROW-BUDGET` checks read only `MEMORY.md` and need none of the
frontmatter fields of section 2: they are useful on the core layer too, and
`/session-debrief` runs them before drafting index rows whenever Python and the
script are available.

## 7. Rollback

Nothing in the core layer depends on any of this. To drop the advanced layer
entirely: delete `last_touched`, `salience`, and `pinned` from every
frontmatter block that carries them, and delete the generated artifacts,
`memory/INDEX.generated.md` (if a local copy exists; it's gitignored, so
there's usually nothing to remove from git) and any saved `--baseline` JSON
files, plus any `areas/<name>/memory/INDEX.generated.md`. Once those fields
are gone, the three advanced-layer hooks in
`/session-debrief`, `/daily-briefing`, and `/memory-checkup` detect their
absence and skip themselves silently, exactly as they do for a team that never
adopted this layer. You're back on the core schema, no residue.

## 8. Federated memory roots (opt-in)

The third step, after the core layer and the salience layer above. Off by
default; nothing in the template assumes it.

### When

One `memory/` folder is right for most teams for a long time. Consider a
second root when one area of the work has its own high-frequency state that
crowds the shared index: a dozen or more active items that only the people
working in that area ever open, while the rest of the team pays for them at
every session start. The signal is the `BUDGET` check turning yellow while
most rows belong to one area.

### How

An area root is `areas/<name>/memory/`, with the same grammar as `memory/`:
a `MEMORY.md` index, one file per item with the frontmatter of
`memory/CLAUDE.md`, an `archive/` folder with its `archive/INDEX.md`. Turning
it on is two edits and no change to any skill:

1. Create `areas/<name>/memory/MEMORY.md` (copy the section headings of
   `memory/MEMORY.md`) and move the area's `project_*` files and their rows
   into it with `git mv`.
2. Add a pointer row to `memory/MEMORY.md` under a `## Areas` heading:

   ```
   ## Areas

   - [Operations](../areas/operations/memory/MEMORY.md) - what the root holds, when to open it.
   ```

   No status, no next action on that row: if it carried them, the primary
   index would grow again at every debrief, which is what the split is for.

Rules that keep the roots coherent:

- **One home per item.** A file lives in the root of the area that owns its
  next action, and its index row lives in that same root's `MEMORY.md`. An
  item that straddles two areas stays where it lives and links the other with
  a `[[wikilink]]`; wikilinks resolve across every root and archive. The gate
  reports the same stem in two roots as `DUP-ROOT`, blocking.
- **`reference_*` and `feedback_*` stay in `memory/`.** They weigh nothing in
  the index and belong to everyone.
- **The daily log stays one folder at the repo root.** It records sessions,
  which cross areas; roots hold state, not diaries.
- **Only `memory/MEMORY.md` is auto-loaded.** Area indexes open on demand: the
  boot sequence in `CLAUDE.md` reads an area's `memory/MEMORY.md` when the
  task touches that area, and `/session-debrief` and `/daily-briefing` follow
  the `## Areas` pointer rows.

### What the tooling does

`scripts/build_index.py`, `scripts/memory_gate.py` and
`scripts/salience_sweep.py` discover roots by themselves: `memory/` plus
every `areas/<name>/memory/` that holds a `MEMORY.md`, nothing else and no
hand-kept list. One generated index per root; wikilinks resolved across all
of them; `BUDGET`, `ROW-BUDGET` and `STALE-INDEX` per index; `INDEX-ROW`
also checks that every area root has its pointer row and every pointer row
has its root. The shell checks in `/memory-checkup` and `/system-checkup`
loop over the same roots. With no area root every one of these runs once, on
`memory/`, and behaves exactly as it did before this section existed.

### Rollback

Move the files and rows back into `memory/` with `git mv`, delete the
`## Areas` section, delete `areas/<name>/memory/`. Nothing else remembers
the root.
