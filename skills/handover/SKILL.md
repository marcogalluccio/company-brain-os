---
name: handover
description: |
  Freezes the current chat's context into a throwaway file so a fresh chat can
  pick up the thread. Touches no memory, no daily log, no git: it is a baton
  between two chats, not a save (persisting goes through /session-debrief).
  Use when the operator says: handover, /handover, pass the baton (to save);
  resume the handover, pick up the handover, resume the chat (to resume).
---

# /handover

Baton pass between two chats. A session is getting long, or you want to close
it, but the work is not done: `handover` captures the state in a temporary
file, and a fresh chat picks up from there with a clean context.

**Not a debrief.** It does not write to `memory/`, does not write to
`daily-log/`, does not commit and does not push anything. If the work needs
to be persisted (project status, session log), that is `session-debrief`.
This is surgical and instant: a single throwaway file, outside the repo.

The file lives at a fixed path: `${TMPDIR:-/tmp}/brain-handover.md`. Outside
the repo (git never sees it), the OS cleans it up, and at most one exists at
a time.

---

## Detect the mode

Two modes in the same skill, distinguished by the operator's intent:

- **Save** - the operator wants to freeze the current chat (save triggers above).
- **Resume** - the operator wants to pick up from a saved handover (resume triggers above).

If the intent is ambiguous, ask which of the two before acting.

---

## Mode ① - Save

1. **Scan the conversation** and reconstruct the state: goal, what is done,
   next step, decisions made, files touched, guardrails, open threads.

2. **Write** `${TMPDIR:-/tmp}/brain-handover.md` with the template below.
   **Adaptive template: include only the sections that actually have
   content** - no empty sections with a placeholder dash. Every save
   **overwrites** the previous file (use the Write tool, never shell
   text-munging: apostrophes in natural language break single-quoted shell
   strings).

   ```markdown
   # Handover - <session title> - <YYYY-MM-DD HH:MM>

   ## Goal
   What we are doing and why (1-3 lines).

   ## Current state
   Where things stand now, what is already done in this chat.

   ## Next step
   The next concrete action to pick up from.

   ## Decisions made
   Choices and constraints settled in chat, so the new chat does not reopen them.

   ## Relevant files / paths
   Files touched or useful, with path, so the new chat does not re-search from scratch.

   ## Do not
   Explicit guardrails: what to avoid, paths already ruled out.

   ## References
   Links to other documents, resources, people, useful numbers.

   ## Open / do not forget
   Open threads, gotchas, anything pending.
   ```

   Get today's date with `date +%Y-%m-%d` (and `date +%H:%M` for the time)
   before writing it into the title; never compute it by hand.

3. **Confirm** in chat: the path plus a 2-line recap of what was captured.
   No approval needed, no preview before writing: it is temporary and zero
   risk. Optionally remind the operator of the trigger for the other chat:
   *"in the new chat: `resume the handover`."*

**Do not** update memory, **do not** write to the daily log, **do not**
perform any git operation. That is the whole point of this skill.

---

## Mode ② - Resume

1. **Read** `${TMPDIR:-/tmp}/brain-handover.md`.
   - If the file **does not exist**, say so calmly ("no saved handover to
     resume") and stop. Never invent context.

2. **Load the context**: absorb the content as the starting state of the new
   chat. Recap in chat where things stood and what the next step is, so the
   operator confirms alignment.

3. **Delete the file** (throwaway): `rm -f "${TMPDIR:-/tmp}/brain-handover.md"`.
   Delete only **after** a successful read, never before.

4. **Confirm**: "Baton taken, file discarded. Picking up from: <next step>."

---

## Rules

- **Never touch memory, daily-log, or git.** That is the clean split from
  `session-debrief`. If persistence is needed, point there instead.
- **One file, fixed path, overwrite.** `${TMPDIR:-/tmp}/brain-handover.md`.
  No timestamped files piling up.
- **Delete after reading, not before.** In Resume mode, the `rm` is the last
  step, only after a successful read.
- **Adaptive template.** Only the sections with real content.
- **Write tool for the file, not `sed`/`perl`/heredoc text-munging.**
  Apostrophes in natural language break single-quoted shell strings.
- **Absolute dates**, from `date +%Y-%m-%d` / `date +%H:%M`.

## Self-improvement

At the end of the run, check it against these friction triggers: **avoidable
round-trip · improvisation · breakage · token waste · operator correction**
(full definitions in `skills/_improvements/capture.md`). If at least one fired,
ask the operator "there was friction on X, should I log it?"; on their ok,
append an entry to `skills/_improvements/friction-log.md` in the format
`capture.md` defines. Clean run: say nothing. Never self-edit this skill;
improvements go through `/skill-improve`.
