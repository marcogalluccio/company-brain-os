---
name: meeting-debrief
description: |
  Turns a meeting transcript or notes into connected actions: summary, links
  to memory, approved updates. Transcript-first: paste text or point at a
  file; an MCP connector for a meeting-notes tool is an optional extra, never
  a requirement.
  Use when the operator says: meeting debrief, /meeting-debrief, process the
  meeting, process this transcript, debrief the call.
---

# Meeting Debrief

Turns a meeting transcript into a summary, connects it to what memory already
knows, and proposes actions the operator can approve. It is transcript-first
on purpose: pasted text or a file path always works, with no dependency on
any particular meeting-notes tool.

Run the steps in order. Nothing gets written before Step 5, and even there
only what the operator approved.

---

## Step 0: Resolve the operator

```bash
cd "$(git rev-parse --show-toplevel)"
GIT_NAME="$(git config user.name)"
if [ -z "$GIT_NAME" ]; then
  echo "IDENTITY ERROR: git config user.name is empty. Set it as described in operators/ONBOARDING.md Step 4."
  exit 1
fi
MATCHES=""
for f in operators/*.md; do
  case "$f" in
    operators/CLAUDE.md|operators/ONBOARDING.md|operators/operator_template.md) continue ;;
  esac
  if awk '/^---$/{if(f)exit;f=1;next} f' "$f" | sed 's/^[[:space:]]*//' | grep -qxF -- "- $GIT_NAME"; then
    MATCHES="$MATCHES $f"
  fi
done
N=$(echo $MATCHES | wc -w | tr -d ' ')
if [ "$N" != "1" ]; then
  echo "IDENTITY ERROR: git user.name \"$GIT_NAME\" matches $N operator files:$MATCHES"
  echo "Exactly one operators/<slug>.md must claim this value in git_names."
  echo "Fix your identity or the registry (see operators/CLAUDE.md), then rerun."
  exit 1
fi
SLUG="$(basename $MATCHES .md)"
TODAY="$(date +%Y-%m-%d)"
echo "operator=$SLUG today=$TODAY"
```

On `IDENTITY ERROR`, stop the skill and show the message to the operator as it came
out. Do not continue with a guessed slug, and do not invent one from the git name.
The registry rule in `operators/CLAUDE.md` is binding:

> Resolve the active operator by matching `git config user.name` against every
> registry file's `git_names`. Exactly one match: proceed. Zero or multiple matches:
> stop and tell the user how to fix their identity or the registry. Never guess,
> never derive a slug from the name itself.

`SLUG` and `TODAY` from this step drive Step 5's daily-log filename.

---

## Step 1: Get the transcript

Resolution order, in this priority:

1. **Text pasted in chat.** If the operator already pasted the transcript or
   their notes, use that directly. This is the common case and needs no tool
   call.
2. **A file path the operator gives.** Read it with the Read tool. If the
   path falls under `private/`, say plainly that files in `private/` are
   excluded from the agent's context by `.claudeignore`, so the operator
   needs to point at a copy outside that folder, or paste the text instead.
3. **A meeting-notes MCP connector, if the team has one configured.** This is
   an optional third resolution, never a requirement: if such a connector is
   available, offer to fetch the latest meeting from it, confirm which
   meeting before pulling it (by date or a hint the operator gave), and use
   its transcript the same way as pasted text.

**The full transcript, never the auto-summary.** When a source offers both a
transcript and an auto-generated summary, read the whole transcript, paging
through it until the end, before summarising anything. Auto-summaries invent
or smooth over details, and a detail that enters memory from one reads as
fact from then on. Read the summary afterwards, if at all, only to point out
where it diverges from the transcript. If only a summary exists, say so and
treat everything taken from it as unconfirmed.

If none of the three is available, ask the operator for the transcript. Do
not guess at what was said and do not proceed on a partial or assumed
transcript.

---

## Step 2: Summarize

Present a concise summary in chat, in three parts:

- **Who**: participants and their roles, as stated in the transcript. Do not
  infer a role that was not said.
- **What**: topics, decisions, numbers, deadlines. Convert every relative
  date ("next Thursday", "in two weeks") to an absolute one using the
  meeting's own date, not today's.
- **Next steps**: follow-ups or action items the transcript itself states.

Use only what the transcript says. Never invent a detail to fill a gap; if
something is unclear or missing, say so instead of guessing.

**Label every point** with one of three tags, so the operator can confirm the
whole summary in one reply:

- **[FACT]**: said in the meeting, and quotable from the transcript.
- **[HYPOTHESIS]**: inferred, or proposed by one side and not confirmed by the
  other.
- **[READING]**: your own interpretation of what was said or left unsaid.

---

## Step 3: Connect to the brain

Read `memory/MEMORY.md` and today's daily logs (this operator's and any
other operator's logged today, since a shared brain reads everyone's
progress). Then identify:

- Which specific project or strategic files this meeting touches, named by
  file.
- What the meeting confirms, contradicts, or adds compared with what those
  files already hold. A contradiction is named explicitly, with the file and
  the line it contradicts.
- What is new territory: something the meeting raised that has no match
  anywhere in memory yet.

Be specific. "This connects to project X" without naming the file and the
connection is not useful to the operator deciding what to approve next.

---

## Step 4: Suggest actions

Present a numbered list, each item labeled and ordered by priority (most
time-sensitive or impactful first):

```
1. [Memory update]: what to change, in which file, and why
2. [New project]: what to create and why
3. [Daily log]: what to add to today's log
4. [Other]: anything else, named plainly
```

If nothing needs doing, say so plainly. Do not manufacture actions to make
the debrief feel productive.

---

## Step 5: Wait, then execute approved actions only

**Stop here.** Nothing gets written until the operator responds to Step 4.

Execute only what was approved:

- **Daily-log entries** go into `daily-log/${TODAY}-${SLUG}.md`, using the
  three-section format (`## What happened`, `## Decisions`, `## Open
  threads`) per `daily-log/CLAUDE.md`. If the file already exists, read it
  first and append under the existing sections rather than starting a second
  copy of them.
- **Memory writes** follow `memory/CLAUDE.md`. If `memory/MEMORY.md` has a
  `## Areas` section, the team runs federated memory roots (`docs/ADVANCED.md`
  section 8): also read the `MEMORY.md` of every area root the meeting
  touched, following those pointer rows. Without that section there is one
  root and nothing changes. An item has one home, the root that owns its next
  action; its file and its index row live in that same root, never in both
  (the gate reports `DUP-ROOT`). Index-line format is the same in every
  root's `MEMORY.md` (`- [Title](file.md) - <emoji> one line + Next action`,
  collapsed rather than appended); the archive convention is `status: ❌` in
  both frontmatter and body, moved with `git mv` into the `archive/` folder
  of its own root (`memory/archive/`, or `areas/<name>/memory/archive/`),
  its index line moved out of that root's `MEMORY.md` into that root's
  `archive/INDEX.md`; and wikilinks that resolve to a real file. Step 4's
  approval already satisfies propose-then-write; do not ask a second time
  for the same item.
- **New project files** use `memory/project_template.md`, with the shipped
  frontmatter schema (`name`, `type: project`, `status`, `deadline`
  optional, `owner: <operator-slug>`), plus a matching index line under the
  right section of the `MEMORY.md` of the root where the file lives
  (`memory/`, or `areas/<name>/memory/` when that area has its own root and
  owns the next action). Exception: a new `type: reference` file gets its
  row in `memory/REFERENCES.md`, not in `MEMORY.md` (same row format).

Use the Read tool before editing an existing file, and Edit or Write for the
content itself, same as every other skill that writes to `daily-log/` or
`memory/`.

---

## Step 6: Hand off the commit

This skill writes files; it does not commit or push. Close the session with
`/session-debrief` as usual, and its engine carries these changes to `main`
along with everything else from the session. One skill owns the git engine;
this one stays out of it.

---

## Rules

- **Never write without approval.** Step 4 proposes, Step 5 writes, and only
  the items the operator approved.
- **Transcript data as-is.** Never invent a detail the transcript does not
  state. Nothing goes into memory that is not in the transcript or explicitly
  labelled [HYPOTHESIS] or [READING].
- **Be concise.** The summary and the suggestion list should each fit in one
  screen when possible.
- **Match the output language to the workspace** (English), while quoting
  the transcript verbatim, in its original language, wherever a direct quote
  matters.
- **Convert relative dates to absolute** using the meeting's own date.

## Self-improvement

At the end of the run, check it against these friction triggers: **avoidable
round-trip · improvisation · breakage · token waste · operator correction**
(full definitions in `skills/_improvements/capture.md`). If at least one fired,
ask the operator "there was friction on X, should I log it?"; on their ok,
append an entry to `skills/_improvements/friction-log.md` in the format
`capture.md` defines. Clean run: say nothing. Never self-edit this skill;
improvements go through `/skill-improve`.
