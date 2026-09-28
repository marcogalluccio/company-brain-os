# Memory layer rules

Read this before writing anything to memory.

## Principle

**Memory is live state. The project folder is detail.** Memory files and the
index (`MEMORY.md`) hold the current status and a pointer to where the real
work lives. The long operational story (build logs, meeting notes, history)
belongs in the project's own folder, not in memory. Nothing gets shortened in
memory until its detail is safe somewhere else first (**preserve-first**, see
below). Nothing is ever lost, only relocated.

## Four categories

- `project_*`: active initiatives with a status and a next action.
- `strategic_*`: long-term positioning and directions.
- `feedback_*`: lessons learned and agent-behavior rules (include the why).
- `reference_*`: pointers to external resources (URLs, repos, dashboards).

## Frontmatter (Core)

Flat schema, no nested wrapper:

```yaml
---
name: <kebab-case-slug>
type: project            # project | strategic | reference | feedback
status: 🟡                # see status scale below
deadline: YYYY-MM-DD     # optional; omit if there is no hard date
owner: <operator-slug>
---
```

Status scale: 🔴 urgent · 🟠 stalled/waiting · 🟡 active · 🟢 on track ·
🔵 wrap-up (done, loose ends open) · ❌ closed.

## Index line format

Every entry in `MEMORY.md` is one line:

`- [Title](file.md) - <emoji> one line + Next action`

The line states three things and nothing more: what it is, what state it is
in, and what happens next. Technical detail, tooling, prices, or anything
else that belongs to the project itself stays out of the index.

## Rules

- **Preserve-first.** Before shortening a memory file's `## Updates`, confirm
  the detail it currently holds is already safe in the project folder. If the
  detail lives only in memory, write it into the folder first, then shorten.
  Update the existing file rather than creating a duplicate; check for one
  before adding a new one.
- **Status and Next action are rewritten, never appended to.** In a project
  file, `## Status` and `## Next action` always describe the present; the
  chronology goes in `## Updates`. Either one longer than an index line is out
  of standard: move the detail to `## Updates` or the project folder.
- **Archive, never delete.** Closing an item means: set `status: ❌` in the
  frontmatter and in the body, move the file to `memory/archive/`, and move
  its index line from `MEMORY.md` to `memory/archive/INDEX.md`. Soft-delete
  only.
- **Don't save what is derivable elsewhere.** Skip anything the repo already
  records (code, git history, a CLAUDE.md) or anything that only matters to
  one conversation.
- **Convert relative dates to absolute** before writing them anywhere.
- **Wikilinks reference the filename stem.** Link related items with
  `[[filename-without-extension]]` in the body, e.g. `[[project_example]]`
  points at `project_example.md`. A file's frontmatter `name:` matches its
  filename stem, so the link, the filename, and the `name:` field are always
  the same string.
- `status:` in the frontmatter schema above applies to `project_*` and
  `strategic_*` files (it drives the emoji on their index line).
  `reference_*` and `feedback_*` files don't carry a status field: they are
  reference material and standing rules, not work with a state.

## Where index rows live

`MEMORY.md` is auto-loaded on every session start and the host tool truncates
it past a size cap, so it carries only rows the daily briefing needs: projects
and strategic directions, plus feedback rules. Two kinds of rows live in
sibling files, read on demand:

- `reference_*` rows in `memory/REFERENCES.md`. The files themselves stay in
  `memory/`; only the row moves. A project that uses a reference links it
  with a `[[wikilink]]`.
- Closed items in `memory/archive/INDEX.md`, with links relative to the
  archive folder (`(project_slug.md)`, no `archive/` prefix).

Same one-line row format everywhere. The scripts in `scripts/` and the
checks in `/memory-checkup` read rows from all three files, and still accept
a repo that keeps everything inline in `MEMORY.md`.

## Memory roots (opt-in)

`memory/` is the primary root. A team that adopts federated roots
(`docs/ADVANCED.md` section 8) keeps one more root per area that needs it,
at `areas/<name>/memory/`, with this file as the single standard for all of
them: same row format, same frontmatter, same archive convention, same
preserve-first rule. An item has one home, the root that owns its next
action; the primary index points at each area root with one row under
`## Areas`, with no status and no next action on it. Without an area root
none of this applies and `memory/` is the whole layer.

## Anti-patterns

- ❌ Relative time words ("today", "next week", "recently") instead of an
  absolute date.
- ❌ Letting the model infer or change a status on its own judgment instead
  of a human decision.
- ❌ Pruning detail from a memory file before the same detail is written
  safely into the project folder (breaks preserve-first).
- ❌ Appending a new dated line to the index without collapsing the previous
  one, letting `MEMORY.md` grow without bound.
- ❌ A `[[wikilink]]` or file path that does not resolve to a real file.
- ❌ The same item in two memory roots (the gate reports `DUP-ROOT`): one
  home, the other root links it.
- ❌ A status or a next action on a `## Areas` pointer row.

## When two debriefs collide

`MEMORY.md` is the file most likely to conflict when two operators close sessions
close together in time: it's the one flat file every debrief touches, so two people
editing it the same day land near each other far more often than in any per-project
file. The index line format (one line per item, self-contained) is what makes almost
every one of these conflicts trivial: both sides added or changed a line, and the fix
is to keep both lines, not to pick one.

A conflict on two adjacent index lines looks like this:

```
<<<<<<< HEAD
- [Website redesign](project_website.md) - 🟡 wireframes approved, next: build homepage.
=======
- [Client onboarding revamp](project_onboarding.md) - 🟢 one-pager drafted, next: share for review.
>>>>>>> origin/main
```

Both lines describe real, current state. The resolution is a union, not a choice:
delete the three marker lines (`<<<<<<<`, `=======`, `>>>>>>>`) and keep both content
lines, in whichever order reads cleanly:

```
- [Website redesign](project_website.md) - 🟡 wireframes approved, next: build homepage.
- [Client onboarding revamp](project_onboarding.md) - 🟢 one-pager drafted, next: share for review.
```

Only stop and read closely if both sides touch the *same* item's line, then it's a
real edit conflict on one project, not two independent additions, and needs an actual
decision about which status is current.

This is still a merge conflict like any other: resolve it inside the rebase, never
abort onto a dirty tree. See the iron rules in the root `CLAUDE.md`'s daily git cycle.

---

Advanced memory (salience scoring, machine index): see `docs/ADVANCED.md`.
