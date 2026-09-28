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
- Creative choices the operator must make by nature (naming,
  tone, scope). That is the work, not friction.
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
pattern: <class id from known-patterns.md>
```

`who` is the operator slug of whoever hit the friction (needed once more
than one operator uses the same skills, so patterns can be attributed). The
third segment of the header line (after the date and the skill name) is
only `friction` (worked but poorly/slowly) or `breakage` (did not work).
`pattern` is optional: before writing the entry, skim
`skills/_improvements/known-patterns.md` and, if the run matches one of its
classes, name the class here. A match is worth more than the entry itself:
`/skill-improve` ranks a class shared across skills above any one-off.

**Where exactly the entry goes.** The new entry is the first dated entry
of the file: directly below the `---` that closes the preamble, above every
existing entry, always above the `## Archive` marker. Before writing, find
the `## Archive` line and confirm the insertion point is above it. An entry
written below the marker is invisible: everything down there is consumed
history and `/skill-improve` never reads it.

**What "open" means.** An entry is open while it has no `consumed:` line.
Only `/skill-improve` adds that line, when it has applied a change; a
proposed fix written under `what:` does not close the entry. Never add a
`consumed:` line from the capture side.
