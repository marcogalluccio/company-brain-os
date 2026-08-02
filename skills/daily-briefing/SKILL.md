---
name: daily-briefing
description: |
  Daily operational briefing built from memory and the last 5 logged days of
  daily logs, read-only on project files except for backstopping today's log.
  Use when the operator says: briefing, /daily-briefing, morning briefing,
  what matters today.
---

# Daily Briefing

Read what memory and the last few logged days already know, and turn it into
one page of "what matters today." This skill is read-only on `memory/` and
`daily-log/` with one narrow exception: if today's log does not exist yet, it
creates the empty skeleton so the file is there even on a day that starts with
a briefing and nothing else.

The briefing is written FOR the current operator, but it reads every
operator's daily logs, not just their own: this is a shared workspace, and a
handoff sitting in a teammate's log two days ago is exactly the kind of thing
a briefing exists to bring forward.

Run the steps in order.

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

On `IDENTITY ERROR`, stop the skill and show the message to the operator as it
came out. Do not continue with a guessed slug, and do not invent one from the
git name. The registry rule in `operators/CLAUDE.md` is binding:

> Resolve the active operator by matching `git config user.name` against
> every registry file's `git_names`. Exactly one match: proceed. Zero or
> multiple matches: stop and tell the user how to fix their identity or the
> registry. Never guess, never derive a slug from the name itself.

`SLUG` and `TODAY` from this step drive Step 2's prioritization (whose open
threads count as "own") and Step 6's backstop filename.

---

## Step 0.5: Freshness check

A briefing built from a stale local copy of `memory/` is worse than no
briefing: it reports state a teammate already changed on origin. Check before
reading anything.

```bash
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "NO-REMOTE: local-only brain, nothing to compare against."
elif git fetch origin main --quiet; then
  AHEAD=$(git rev-list --count origin/main..HEAD)
  BEHIND=$(git rev-list --count HEAD..origin/main)
  echo "ahead=$AHEAD behind=$BEHIND"
else
  echo "FETCH FAILED: could not reach origin; freshness unknown."
fi
```

- `BEHIND > 0`: recommend running `/sync` before trusting this briefing. Local
  `memory/` is stale.
- `AHEAD > 0`: note in the briefing that local `main` is ahead by N commits
  (a deferred push from an earlier session, most likely), so the shared copy
  does not have it yet.
- `FETCH FAILED`: say plainly that freshness could not be checked. Never treat
  a failed fetch as "up to date": that reads the last successful fetch's
  state, which may be hours or days old, as current.

This step is read-only. It never fetches to change anything, only to compare.

---

## Step 1: Read memory

`memory/MEMORY.md` is the primary source. For every 🔴 or 🟠 row in it, read
the linked project file and pull its `## Status`, `## Next action`, and
`deadline` frontmatter (if set). Skip `memory/*_template.md` and any file
whose stem ends in `_example`, per the shipped convention.

**Advanced layer, if adopted.** If the team has adopted `docs/ADVANCED.md`,
project files carry `salience` and `last_touched` frontmatter fields; recompute
salience live for every project using the deterministic formula there
(read-only, write nothing), rank the top 5, and open the briefing with a
"Top 5 now" list ahead of the Today section. If those fields are not present,
the team has not adopted the layer: skip this silently, with no mention of it
anywhere in the output.

---

## Step 2: Read the last 5 logged days

"Last 5 logged days" means the 5 most recent dates that actually have a log
file, not the 5 calendar days ending today. In a workspace with a logging
gap, those two are not the same thing, and there is no portable way to close
that gap by computing calendar dates (the portability rule bans `date -d`,
`date -v`, and `date -j`). Say what this actually selects, not what it would
select if every day had a log.

```bash
cd "$(git rev-parse --show-toplevel)"
DATES="$(ls daily-log/ 2>/dev/null \
  | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}-.+\.md$' \
  | sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2})-.*/\1/' \
  | sort -u | tail -5)"
for d in $DATES; do
  for f in daily-log/${d}-*.md; do
    [ -f "$f" ] && echo "$f"
  done
done
PREV_LOGGED="$(printf '%s\n' $DATES | awk -v t="$TODAY" '$0 < t' | tail -1)"
echo "previous_logged_day=${PREV_LOGGED:-none}"
```

`DATES` is a date filter, not an operator filter: read every file each date
produces, regardless of whose slug is in the filename, per the
shared-workspace awareness noted above. `PREV_LOGGED` is the most recent
logged date strictly before `TODAY`, found by plain string comparison on the
ISO-formatted dates (which sorts chronologically with no arithmetic); empty
means no earlier log exists yet, on a brand-new brain.

**Staleness check.** Compare `PREV_LOGGED` to `TODAY` yourself, as two ISO
date strings already in hand: deciding whether they are consecutive calendar
dates needs no `date` command, just reading them. If they are not consecutive
(any gap, even one day), say so plainly at the very top of the briefing,
before anything else, e.g. "most recent prior log is 2026-07-19, the
workspace has a logging gap." Never let an old thread from a gapped log read
as fresh just because it happened to be selected into this window.

Extract, in priority order, and tag every item with its source date (the
`YYYY-MM-DD` the filename it came from):

- `## Open threads` bullets, tagged with their source date: candidates for
  Today. Prioritize bullets from the current operator's own file
  (`daily-log/*-${SLUG}.md`) first.
- Bullets in another operator's log that name the current operator by name or
  slug (a cross-operator handoff, e.g. "waiting on jane to send..."), tagged
  with their source date: Today, since it names someone specific to act on
  it.
- `## What happened` bullets from the file at `PREV_LOGGED` (any operator),
  tagged with that date: the Previous logged day recap. If `PREV_LOGGED` is
  empty, there is nothing to recap.
- An open thread that reads as substantially the same item across 2 or more
  of the window's logged dates (same operator repeating it day to day, or the
  same blocker named by two different operators), tagged with its earliest
  source date: flag 🔴 stuck rather than routing it to Watch as a fresh item.

---

## Step 3: Optional connectors

If the team has calendar or email MCP connectors, fetch today's events and
unanswered threads into Today or Watch.
Skip silently when none are configured: no errors, no placeholder sections.

---

## Step 4: Prioritize

Sort what Steps 1 through 3 gathered into sections. Every item carries the
source date Step 2 tagged it with:

- **Today** (max 5-7 concrete actions, most urgent first): 🔴 memory
  projects first, then the current operator's own open threads, then items
  flagged 🔴 stuck, then anything else that is actionable today.
- **Watch**: monitoring items, anything waiting on an external reply, 🟠/🟡
  memory projects that need attention soon but not today.
- **Previous logged day (`PREV_LOGGED`)**: the recap pulled in Step 2. Omit
  this section entirely when `PREV_LOGGED` is empty.
- **Upcoming**: items with a `deadline` in memory within the next 30 days.
- **Notes**: context that does not fit above but is worth keeping visible.

No item appears in more than one section. Omit any section with nothing in
it rather than showing it empty. An item waiting on someone else's reply is a
Watch item, not a Today action: "waiting" is a status, not a task. If Step 2
flagged a staleness gap, that notice leads the briefing ahead of every
section below, not folded into one of them.

---

## Step 5: Render

Write the briefing to `${TMPDIR:-/tmp}/brain-briefing.html` using the
standard template from `skills/html-preview/SKILL.md` (title "Daily
Briefing"; do not duplicate its `<style>` block here, reference it and reuse
it as-is). Order: the staleness notice from Step 2 first, if any; then the
optional "Top 5 now" list from Step 1 when the advanced layer is adopted;
then Today, Watch, Previous logged day (`PREV_LOGGED`), Upcoming, Notes, each
only if it has content.

```bash
FILE="${TMPDIR:-/tmp}/brain-briefing.html"
cat > "$FILE" <<'HTML'
<!-- the rendered briefing, using the standard html-preview template -->
HTML
```

Open it with the portable open block:

```bash
( open "$FILE" 2>/dev/null || xdg-open "$FILE" 2>/dev/null || start "" "$FILE" 2>/dev/null ) \
  || echo "Open this file in your browser: $FILE"
```

Then close with a 3-line chat summary: how many actions are in Today, how
many are urgent (🔴), and anything odd worth flagging (a stale sync, a fetch
failure, an ambiguous project status that got skipped rather than guessed).

---

## Step 6: Backstop today's log

```bash
LOG="daily-log/${TODAY}-${SLUG}.md"
if [ -f "$LOG" ]; then
  echo "BACKSTOP: $LOG already exists, left untouched"
else
  echo "BACKSTOP: creating $LOG"
fi
```

If the check reports the file is missing, create it with the Write tool (not
a heredoc, to match how every other skill writes file content) using the
exact skeleton `daily-log/CLAUDE.md` defines, with `${TODAY}` and `${SLUG}`
substituted for the literal values Step 0 printed:

```markdown
# ${TODAY} - ${SLUG}

## What happened

## Decisions

## Open threads
```

Never overwrite an existing file. If Step 6 finds one already there, an
earlier session today (a debrief, a granola-style meeting log, or an earlier
briefing) already owns it, and this step is a no-op.

---

## Rules

- **Read-only**, with exactly one exception: the log backstop in Step 6.
  This skill never creates or edits a memory file, never edits another
  operator's log, and never writes anything into today's log beyond the
  empty skeleton.
- **Lookback is the last 5 logged days**, the most recent dates that actually
  have a log file, not a 5-calendar-day window. A logging gap can pull old
  threads into that window, which is why every extracted item carries its
  source date and a gap before `PREV_LOGGED` gets flagged at the top rather
  than presented as fresh.
- **Max 5-7 items in Today.** Prioritize ruthlessly; move the rest to Watch
  or Notes rather than padding Today past what is actually urgent.
- **No duplicates across sections.** Each item appears exactly once.
- **Omit empty sections.** Do not render a heading with nothing under it.
- **Graceful degradation.** Missing calendar/email connectors produce silence
  in Step 3, never an error and never an empty section.
- **Ask instead of guessing.** When a project's status is ambiguous, or a
  daily-log bullet is not clearly resolved or still open, say so and ask
  rather than placing it in a section on a guess.
- **English** for all output, regardless of the language a source log or
  memory file was written in.

## Self-improvement

At the end of the run, check it against these friction triggers: **avoidable
round-trip · improvisation · breakage · token waste · operator correction**
(full definitions in `skills/_improvements/capture.md`). If at least one fired,
ask the operator "there was friction on X, should I log it?"; on their ok,
append an entry to `skills/_improvements/friction-log.md` in the format
`capture.md` defines. Clean run: say nothing. Never self-edit this skill;
improvements go through `/skill-improve`.
