# Friction capture protocol

Read this file only when you are about to log friction. The trigger keywords
live in each skill's `## Self-improvement` footer; this file holds the full
definitions, the entry format, and the rules. Consumed by `/skill-improve` (or
whatever you name the skill that reads this log to propose fixes).

## When a run counts as friction

At least one trigger must fire, AND it must point to a **defect in the
skill**, not an intrinsic difficulty of the task.

1. **Avoidable round-trip:** you asked the operator for something a
   better-designed skill would have read or inferred (e.g. a deadline
   already in frontmatter).
2. **Improvisation:** you deviated from the skill's steps because a step
   was missing, ambiguous, or wrong.
3. **Breakage:** a step errored, or produced something that had to be
   redone.
4. **Token waste:** you redid work already available (re-read a file,
   recomputed something already on hand).
5. **Operator correction:** the output had to be corrected by the operator
   before it was usable.

Does NOT count (keeps the log clean):
- Creative choices the operator must make by nature (narrative arc,
  palette). That is the work, not friction.
- One-off environment hiccups unrelated to the skill (a network timeout).

## Rules

- **Offer, never auto-write.** When a trigger fires, ask the operator
  whether to log it, and append only on their ok.
- **Silent on clean runs.** No friction → write nothing, say nothing.
- **Operator can self-flag.** If the operator says a run was clunky, log it
  even if autojudgment missed it.
- **Never self-edit the skill.** Improvements happen only via the skill
  that reads this log and proposes a diff for approval; nothing edits a
  skill directly from a friction entry.

## Entry format

Append to `friction-log.md`, newest first, above the `## Archive` marker:

```markdown
## YYYY-MM-DD · <skill-name> · <friction|breakage>
who: <operator-slug>
what: one line, what went wrong and which step
cost: one line, round-trip / redo / tokens / correction
```

`who` is the operator slug of whoever hit the friction (needed once more
than one operator uses the same skills, so patterns can be attributed). The
third segment of the header line (after the date and the skill name) is
only `friction` (worked but poorly/slowly) or `breakage` (did not work).
