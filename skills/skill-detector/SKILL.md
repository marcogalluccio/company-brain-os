---
name: skill-detector
description: |
  Spots recurring manual workflows that deserve to become a skill, proposes
  up to three candidates with an honest worth-it bar, and scaffolds the
  SKILL.md for one on explicit approval. Never writes without approval, and
  never creates a candidate that duplicates an existing skill or a defect in
  one (that is /skill-improve).
  Use when the operator says: skill detector, /skill-detector, should this be
  a skill, detect skills.
---

# Skill Detector

Finds the manual, multi-step work that keeps happening by hand and is stable
enough to write down, and turns the strongest cases into a proposal. It never
invents a candidate to have output, and it never writes a skill file without
the operator picking that exact candidate first.

**What it does:** collects evidence, proposes up to three candidates,
scaffolds one SKILL.md per explicit approval.
**What it does not do:** fix an existing skill (that is `/skill-improve`),
write more than one scaffold per approval, or guess at a step it has no
evidence for (the scaffold marks those gaps openly instead).

Run the steps in order.

---

## Step 1: Collect evidence

Evidence comes from three sources, read in this order. Weigh them together:
a candidate backed by two sources is stronger than one backed by a single
mention in the current conversation.

### (a) The current conversation

Look back over this session for multi-step procedures that were carried out
by hand: several distinct actions run in sequence to reach one outcome,
especially if the operator asked for the same kind of outcome before (in this
conversation or, as far as you can tell, in general). A single command is not
a procedure. Note what was done, in what order, and whether anything about it
felt like it was already a familiar routine to the operator.

### (b) The last 14 logged days of daily logs

"Last 14 logged days" means the 14 most recent dates that actually have a
daily-log file, not a 14-calendar-day window; a workspace with a logging gap
does not have a log for every calendar day, and there is no portable way to
compute "14 days ago" without the banned `date -j`/`-v`/`-d` flags. Enumerate
with `find`, never a bare glob: a glob with zero matches is fatal in zsh, and
a 14-day window can easily contain a day with no log at all.

```bash
cd "$(git rev-parse --show-toplevel)"
DATES="$(find daily-log -maxdepth 1 -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md' 2>/dev/null \
  | xargs -n1 basename 2>/dev/null \
  | sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2})-.*/\1/' \
  | sort -u | tail -14)"
for d in $DATES; do
  find daily-log -maxdepth 1 -name "${d}-*.md" 2>/dev/null
done
```

Read every file this prints, from every operator (a routine that recurs
across two different people's logs is stronger evidence than the same person
repeating it). Inside each file, look for two patterns:

- The same activity described in `## What happened` on two or more of the
  window's dates. Judge this by what was actually done, not by matching
  words: "pulled the overdue invoices and mailed the reminders" and
  "sent this week's payment reminders" are the same recurring activity even though neither
  sentence repeats the other's words.
- A `## Open threads` item that recurs across two or more dates and describes
  a process gap ("still doing X by hand every time", "need a repeatable way
  to Y") rather than a specific piece of unfinished work. An open thread that
  just names an unfinished task, with no process complaint in it, is not
  evidence for a skill.

Tag every finding with the dates it came from; those dates are what makes the
evidence in Step 2 verifiable rather than asserted.

### (c) Open friction-log entries describing a missing flow

Read `skills/_improvements/friction-log.md`, entries above the `## Archive`
marker only (below it, entries are already consumed). Every entry is filed
under the skill that was running at the time (per the header format in
`skills/_improvements/capture.md`), but that does not mean every entry is
about that skill's own steps. Read the `what` line and sort each entry into
one of two buckets:

- **Defect in the named skill:** the entry says that skill's own step was
  missing, wrong, or produced something that had to be redone. This belongs
  to `/skill-improve`, not here. Leave it alone.
- **Missing flow:** the entry says the operator wanted an outcome the named
  skill was never built to produce, an entirely different job that just
  happened to be logged against whatever skill was running when it came up.
  This is evidence for a candidate, decoupled from the skill it was filed
  under.

Only the second bucket feeds Step 2.

### Cross-check against the existing suite

Before turning anything into a candidate, run `ls skills/` and read the
one-line purpose of anything that looks adjacent. If an existing skill
already covers the activity, even partially, this is a `/skill-improve` case
for that skill, not a new candidate: route it there in Step 2's write-up
instead of proposing it. `skills/_improvements/` is not a skill; skip it in
this listing.

---

## Step 2: Propose candidates

Propose at most 3 candidates per run, strongest evidence first. If nothing
gathered in Step 1 clears the bar below, say plainly that no candidate
emerged this run and stop. Never invent one just to have output; a run that
finds nothing is a correct, useful result.

**The worth-it bar.** Recurring, multi-step, and stable enough to write
down. A two-step workflow run twice is not a skill yet, it is a coincidence
waiting for a third data point. Be honest about this in the write-up below,
even when it means saying a candidate is not there yet.

For each candidate, present:

- **Name**: kebab-case, exactly what the folder will be (`skills/<name>/`).
- **Evidence**: the dates and quotes from Step 1, not a paraphrase of "this
  seemed to come up".
- **Trigger phrases**: what the operator would plausibly say to invoke it.
- **Outline**: 3-6 steps, at the same level of detail the evidence actually
  supports.
- **Touches**: which files, folders, or tools the flow reads or writes.
- **Worth it?**: one honest line against the bar above. A candidate that is
  recurring but only two steps, or multi-step but only seen once, says so
  here instead of being proposed as stronger than it is.

Then stop and wait. Do not scaffold anything until the operator names which
candidate, if any, to build.

---

## Step 3: Scaffold on approval, one candidate at a time

Only after the operator picks a specific candidate. One scaffold per
approval; if they approve two, do them as two separate passes through this
step, not one.

Create `skills/<name>/SKILL.md`, flat (`skills/<name>/SKILL.md`, never a
category subfolder or a nested path), with:

**Frontmatter**, the frontmatter shape every skill uses, filled with the agreed name, description,
and trigger phrases from Step 2:

```yaml
---
name: <agreed-name>
description: |
  <One line: what the skill does and its boundaries.>
  Use when the operator says: <the agreed trigger phrases, including /<name>>.
---
```

**A header note**, directly under the title, stating plainly that this file
is a scaffold: the steps below were drafted from the evidence in the
detection run that proposed it, not from a real execution of the flow, and
any step marked `[fill in during first real run]` is deliberately
incomplete. That marker is allowed here, and only here: the first time this
skill actually runs for real, the gap gets filled in from what actually
happened, the same way every other skill in this suite was written down after
someone did the thing by hand at least once.

**The steps**, as numbered sections, one per item in the agreed outline: for
whatever part of a step the evidence pinned down (a specific command, a
specific file, a specific tool call), write it out concretely; for whatever
part it did not, write `[fill in during first real run]` instead of guessing
a plausible-looking command that was never actually observed. A scaffold
that pretends to know a step it does not is worse than one that says so.

**A `## Rules` section**, seeded only with the workspace invariants that
actually apply to this flow, not the full boilerplate list from every other
skill: propose-then-write if the flow touches `memory/` or another shared
file, never force-push and never auto-resolve conflicts if it touches git at
all, one action per approval if it repeats a write. Leave out anything the
flow does not touch.

**The footer**, the Self-improvement footer, verbatim, byte-identical to every other skill in the
suite: copy it byte-for-byte from the closing section of any existing skill
(for example `skills/sync/SKILL.md`), never retype it from memory.

**Tell the operator, once the file is written:** with the container
registration in place (`.claude/skills -> ../skills`), the new skill is
discoverable on every machine the moment that machine's next `/sync` pulls
this commit. There is no per-machine step beyond the one-time link each
operator already set up in `SETUP.md`; nobody needs to touch anything to
start seeing `/<name>` as an option.

---

## Rules

- **Propose, never auto-create.** Step 2 ends in a wait, not a write.
- **Evidence-based only.** Every candidate traces to dates and quotes from
  Step 1, not to a hunch. No open evidence, no candidate.
- **Route correctly.** An activity an existing skill already covers, even
  partially, is a `/skill-improve` case, not a new candidate; a friction-log
  entry describing that named skill's own defect belongs there too, never
  here.
- **One scaffold per approval.** Multiple approved candidates are multiple
  passes through Step 3, not one batch write.
- **Honest worth-it bar.** A two-step workflow run twice is not a skill yet;
  say so rather than rounding a weak candidate up to make the list look
  fuller.

## Self-improvement

At the end of the run, check it against these friction triggers: **avoidable
round-trip · improvisation · breakage · token waste · operator correction**
(full definitions in `skills/_improvements/capture.md`). If at least one fired,
ask the operator "there was friction on X, should I log it?"; on their ok,
append an entry to `skills/_improvements/friction-log.md` in the format
`capture.md` defines. Clean run: say nothing. Never self-edit this skill;
improvements go through `/skill-improve`.
