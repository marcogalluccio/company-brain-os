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
one to take. The count reads the open section only (above `## Archive`)
and flags entries whose skill name matches no folder under `skills/`;
misfiled open entries are surfaced by the Step 1 archive check, not ranked
here:

```bash
cd "$(git rev-parse --show-toplevel)"
awk '/^## Archive/{exit} /^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] /{print}' skills/_improvements/friction-log.md \
  | sed -E 's/^## [0-9-]+ · ([^ ]+) · .*$/\1/' | sort | uniq -c | sort -rn \
  | while IFS= read -r line; do
      name="$(printf '%s\n' "$line" | sed -E 's/^ *[0-9]+ //')"
      if [ -d "skills/$name" ]; then echo "$line"; else echo "$line   OWNERLESS (no skills/$name/)"; fi
    done
```

An `OWNERLESS` line is not a skill to improve; it is an entry to route
(Step 1, "Ownerless entries"). Present those separately from the ranking.

## Workflow

### 1. Gather

- Find and read the target skill's `SKILL.md` at `skills/<skill-name>/SKILL.md`
  (the suite is flat: one directory per skill, no category subfolders), plus
  any supporting file it references, if relevant to the friction.
- Read `skills/_improvements/friction-log.md` and keep only the **open**
  entries for that skill: entries above the `## Archive` marker whose header
  names the skill. Open is defined by the entry, not by its position: an
  entry with no `consumed:` line is open wherever it sits. Check the archive
  for misfiled ones, and treat any it finds as open, saying so to the
  operator:

  ```bash
  H="$(awk '/^## Archive/{a=1} a' skills/_improvements/friction-log.md | grep -cE '^## [0-9]{4}-[0-9]{2}-[0-9]{2} ')"
  C="$(awk '/^## Archive/{a=1} a' skills/_improvements/friction-log.md | grep -c '^consumed:')"
  [ "$H" = "$C" ] && echo "archive ok: $H entries, all consumed" || echo "MISFILED: $H archived entries, $C consumed lines; the difference is open"
  ```

- **Ownerless entries.** An entry whose skill name matches no folder under
  `skills/` (a cross-skill pattern, an external plugin, the harness) is
  reached by no `/skill-improve <name>` run. When you meet one, route it to
  exactly one of three places and say which: (a) a pattern that recurs
  across skills becomes a class in `skills/_improvements/known-patterns.md`,
  plus one line citing that class from an executable step of every skill it
  touches, because a note no step opens closes no loop; (b) an entry whose
  tag names another skill of the suite is refiled under that skill's name;
  (c) a cause outside the repo is archived as not fixable in-repo, with the
  substitute habit written in its `consumed:` line. The rules are in
  `docs/SKILL-MAINTENANCE.md` section 5.

### 2. Diagnose

- Group the open entries by pattern: same step, same recurring trigger.
  Then open `skills/_improvements/known-patterns.md` and check every group
  against its classes; an entry that already carries a `pattern:` line
  names its class. A group that matches a class is a suite-wide pattern,
  not a defect of this one skill: the proposal names every skill the class
  touches, and the fix is usually the same line in each.
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
- Close each consumed entry by appending one line to it,
  `consumed: YYYY-MM-DD · <what changed, one line>`, then move the whole
  entry from the open section to below the `## Archive` marker. The line is
  the marker of a closed entry; the move is housekeeping. Never move an
  entry without the line, and never add the line to an entry whose change
  was not applied.
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
