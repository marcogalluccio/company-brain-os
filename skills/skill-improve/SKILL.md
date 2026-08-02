---
name: skill-improve
description: |
  Reads a skill's SKILL.md plus its open friction-log entries and proposes
  concrete diffs to make it more effective and efficient. Read-only until
  approval: applies only diff by diff, never rewrites wholesale, and never
  creates a new skill from scratch (that is /skill-detector).
  Use when the operator says: /skill-improve, skill-improve, improve the X
  skill, evolve the X skill.
---

# Skill Improve

A meta-skill: it turns a skill's recorded friction into an approvable
improvement proposal. It never self-applies. It proposes a diff, the
operator decides, diff by diff.

## Input

`/skill-improve <skill-name>`, e.g. `/skill-improve sync`. If the name is
omitted, rank skills by number of open friction-log entries and ask which
one to take.

## Workflow

### 1. Gather

- Find and read the target skill's `SKILL.md` at `skills/<skill-name>/SKILL.md`
  (the suite is flat: one directory per skill, no category subfolders), plus
  any supporting file it references, if relevant to the friction.
- Read `skills/_improvements/friction-log.md` and keep only the **open**
  entries for that skill: entries above the `## Archive` marker whose header
  names the skill.

### 2. Diagnose

- Group the open entries by pattern: same step, same recurring trigger.
- A recurring pattern outranks a one-off; say so explicitly and rank
  patterns above isolated entries.
- No open entries for that skill: say so and stop. No proposal without
  data. The only exception is a light qualitative review, and only if the
  operator explicitly asks for one.

### 3. Propose (on screen, write nothing yet)

For each pattern, present:

- **Symptom**: what happens and how often, citing the entry dates.
- **Cause**: which part of the SKILL.md causes it.
- **Proposed diff**: the exact change to the SKILL.md, before to after,
  aimed at both effectiveness and efficiency.
- **Cost/risk**: what could break. Conservative default: additive change
  before rewrite.

Present every proposal, then stop and wait for the operator's approval,
diff by diff.

### 4. Apply approved diffs only

- For each accepted proposal, edit the SKILL.md with a targeted edit, never
  a full rewrite of the file.
- Move the consumed entries from the open section to below the `## Archive`
  marker in the friction-log, noting the date and what changed.
- If the team routes structural work through feature branches (see
  `docs/GOVERNANCE.md` step 2 if the team has adopted it), skill edits
  belong on one, not on a direct commit to main.

## Rules

- **Never apply without explicit approval**, judged diff by diff.
- **Additive first.** Do not touch logic that already works unless it is
  the recorded cause of the friction. The goal is to refine, not rewrite.
- **No proposals without data.** An empty log for that skill means no diff.
- **One skill at a time.**
- **Never modify a skill's `## Self-improvement` footer.** It is standard
  and identical across the suite; changing it is a change to
  `skills/_improvements/capture.md`, a different decision than this one.

## Self-improvement

At the end of the run, check it against these friction triggers: **avoidable
round-trip · improvisation · breakage · token waste · operator correction**
(full definitions in `skills/_improvements/capture.md`). If at least one fired,
ask the operator "there was friction on X, should I log it?"; on their ok,
append an entry to `skills/_improvements/friction-log.md` in the format
`capture.md` defines. Clean run: say nothing. Never self-edit this skill;
improvements go through `/skill-improve`.
