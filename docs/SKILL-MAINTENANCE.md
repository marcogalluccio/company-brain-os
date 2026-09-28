# Maintaining the skills suite

How a skill stays small while it learns from use. The routines that touch
the suite (`/skill-improve`, `/skill-detector`, `/system-checkup`) apply
these rules; this file is where they are written down once. Nothing here is
loaded on session start: it is read when a skill is reviewed, not when it
runs.

## 1. Hot text and reference files

A `SKILL.md` is read in full every time the skill runs, so every byte in it
is paid for on every run. The file holds only what the common path needs:

- the steps, in order, with the commands an ordinary run executes;
- the classification lists (what counts as X, what goes where);
- the common outcomes of each command, plus one pointer to the rare ones.

What fires rarely leaves the hot text and lives in `skills/<name>/reference/`:

- rare outcomes and their procedures (an exit code seen once a month);
- branch procedures for exceptional states (a legacy layout, a migration);
- the history of the incidents that shaped the skill (section 3).

A reference file opens with a one-line header saying when it is read
("Open only when ..."), so a reader knows they are off the common path. The
hot text keeps a one-line pointer to it at the exact step where the rare
case surfaces, never in a preamble list of "see also".

When a script owns the rare outcomes (as `scripts/debrief-push.sh` does for
the debrief), the script prints the path of the reference on every non-zero
exit, so the agent opens the file instead of improvising.

## 2. The symmetric trap: when moving text out costs more than it saves

Moving a block into a reference file, or replacing it with a pointer to
another file, only pays off when the reader would not have opened the target
anyway. The rule:

> Deduplicate by pointer only toward a file the flow already reads on that
> path.

Two tests before moving a block out, both measured, never guessed:

1. **Is the target already in the reading flow?** If the step that needs
   the text would open the target file anyway, a pointer saves the bytes. If
   the agent has to open a new file just to follow the pointer, the pointer
   costs the whole target file, not the bytes removed.
2. **Is the target smaller than what leaves?** A pointer to a file larger
   than the removed block is a net loss every time the pointer is followed.
   `wc -c` on both sides before deciding.

A block that fails either test stays in the hot text, however repetitive it
looks. The same three lines in two skills cost less than a hop the agent
takes on every run.

The corollary for a skill that is not fat: apply the method, not a diet. If
a pass over the hot text finds no rare material, the right outcome is
"nothing to move", not a forced cut.

## 3. Incidents: a citation in the hot text, the story in the reference

A rule born from an incident is written as the rule, with a short label as
its citation: "never X (see `reference/incidents.md`, row `<label>`)". The
story lives in `skills/<name>/reference/incidents.md` as a table:

| Label | What happened | Rule that came out of it |
|---|---|---|

The table is read when the skill is reviewed, never when it runs. It is also
the place to check before removing a rule: a rule with a row here was paid
for once already. Labels are short and stable (`zsh-loop-lookup`, not a
date), so the hot text never carries a timeline.

## 4. Descriptions

The `description` field of every skill is loaded into context on every
session, whether or not the skill runs, so the whole suite pays for every
byte of every description. Trim across the suite with one rule, applied to
all skills in one pass rather than skill by skill:

- the description says what the skill does and when it fires;
- prose examples that restate the trigger words go;
- explanations of how the skill works go to the body.

A short description with a clean trigger list is the model. A long one with
narrative examples is the one most likely to be invoked by mistake, and the
one that collides with its neighbours' triggers.

## 5. Friction log hygiene

The capture protocol is `skills/_improvements/capture.md`; these are the
rules that keep the log useful over months.

- **Position.** A new entry is the first dated entry of the file: directly
  below the preamble's closing `---`, above every existing entry, always
  above the `## Archive` marker. Everything below the marker is consumed
  history and is ignored by `/skill-improve`; an entry written down there is
  invisible.
- **Open means "no `consumed:` line".** The criterion is the line, not the
  position. `/skill-improve` adds `consumed: YYYY-MM-DD · <what changed>`
  when it turns an entry into an accepted change, then moves the entry
  below `## Archive`. An entry that carries a proposed fix but no
  `consumed:` line is still open: a candidate fix is not an applied fix.
- **Ownerless entries.** An entry whose skill name matches no folder under
  `skills/` (a cross-skill pattern, an external plugin, the harness itself)
  is reached by no `/skill-improve <name>` run and recurs until someone
  files it. Each one goes to exactly one of three places: (a) a pattern
  that recurs across skills becomes a class in
  `skills/_improvements/known-patterns.md`, plus one line citing it from an
  executable step of every skill it touches (a note no step opens closes no
  loop); (b) an entry whose tag names another skill of the suite is refiled
  under that skill; (c) a cause outside the repo (a plugin, the harness) is
  archived as "not fixable in-repo", with the substitute habit written in
  its `consumed:` line.

## 6. Retiring a skill

A skill is retired when its trigger no longer exists in the flow, not when
it has merely gone unused for a while: a seasonal skill sits idle for months
and is still alive. Before the folder goes:

1. **List its functions**, one per line, read from its own steps.
2. **Name an heir per function**, or write "dropped" and why. A function
   with no heir and no reason is the signal that the skill is not ready to
   go.
3. **List the couplings**: every file that names the skill
   (`grep -rn "<name>" .`, or `git grep -n "<name>"`, over every tracked
   file, not only `*.md`: a path list under `.github/` or a test under
   `scripts/tests/` can name a skill too), and every skill whose trigger
   words or "not for" lines point at it.
4. **One pull request**: the heirs' edits, the couplings redirected, the
   README matrix and counts updated, a `CHANGELOG` line, and the folder
   removed last, in the same change.

The alternative is a rethink: keep the skill, rewrite it around the one
function that has no heir, cut everything else. Which of the two applies is
the operator's decision, taken before any edit.
