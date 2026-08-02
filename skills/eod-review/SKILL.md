---
name: eod-review
description: |
  End-of-day review: a read-only audit of your own day plus a digest of what
  teammates pushed since your last logged day, ending in numbered copy-paste
  fix proposals. Writes nothing into the repository except an approval-gated
  friction-log entry, and invokes no other skill.
  Any operator can run it; there is no privileged reviewer.
  Use when the operator says: eod, /eod-review, end of day review, close the
  day, review the day.
---

# End-of-Day Review

The closing ritual. It reads the day, cross-checks it against the conventions
this brain runs on, and hands back a numbered list of fixes for you to apply.
It changes nothing about the work: no commits, no memory edits, no branch
deletions, no bookmark written back into the log. The only file it creates is a
temporary HTML report outside the repository, and the only line it can ever add
inside the repository is a friction-log entry you approve first, as every skill
in this suite does.

Any operator can run it, and everyone gets the same skill. It is not a
policing tool: the teammate digest exists because a shared brain is easier to
trust when you can see what moved in it while you were working, and because a
commit with no log entry is a gap someone has to notice. Attribution is by git
author name, which is a review aid and not a security boundary.

The report is a mirror. The chat output is the actionable part.

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

`SLUG` decides which daily log is "yours" and which registry files are
"teammates". `TODAY` bounds the whole audit.

**Then refresh the view of origin, and be honest when you cannot.**

```bash
if ! git remote get-url origin >/dev/null 2>&1; then
  FETCH_NOTE="LOCAL-ONLY: no origin remote configured; the teammate digest reads local history only."
elif git fetch origin --quiet; then
  FETCH_NOTE=""
else
  FETCH_NOTE="FETCH FAILED: could not reach origin; teammate data below may be out of date."
fi
echo "${FETCH_NOTE:-fetch ok}"
```

A failed fetch is never "up to date": it silently reuses whatever the last
successful fetch left behind, which can be days old. When `FETCH_NOTE` is
non-empty, put it verbatim in the report header and repeat it in the chat
summary, then continue with the audit. This skill is non-blocking by design;
every collector that fails degrades to a note instead of stopping the run.

---

## Step 1: Collect, with no filtering yet

Three collectors: your day, the teammate window, the pull-request queue. Read
them all before judging anything in Step 2.

### 1a: Your day

```bash
cd "$(git rev-parse --show-toplevel)"
if git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then REF=origin/main; else REF=HEAD; fi
MY_LOG="daily-log/${TODAY}-${SLUG}.md"
if [ -f "$MY_LOG" ]; then
  MY_LOG_EXISTS=yes
  MY_LOG_BULLETS=$(grep -cE '^[[:space:]]*[-*] ' "$MY_LOG" || true)
else
  MY_LOG_EXISTS=no
  MY_LOG_BULLETS=0
fi
# Every git name the registry claims for you becomes an --author pattern; git ORs
# repeated --author flags, so a second machine with a different spelling still
# counts as you. set -- builds the flag list without needing shell arrays.
set --
while IFS= read -r NAME; do
  [ -n "$NAME" ] || continue
  set -- "$@" --author="$NAME"
done <<YAML
$(awk '/^---$/{if(f)exit;f=1;next} f' "operators/${SLUG}.md" | awk '/^git_names:/{g=1;next} g&&/^[[:space:]]*-[[:space:]]+/{sub(/^[[:space:]]*-[[:space:]]+/,"");print;next} g&&/^[^[:space:]]/{g=0}')
YAML
if [ "$#" -eq 0 ]; then
  echo "REGISTRY: no git_names parsed for $SLUG, commit attribution skipped"
  MY_COMMITS=""
else
  MY_COMMITS=$(git log HEAD "$REF" "$@" --since="$TODAY 00:00:00" --pretty=format:'%h|%an|%s' 2>/dev/null)
fi
WORKING_TREE=$(git -c core.quotePath=false status --short --untracked-files=all)
TREE_BEYOND_LOG=$(printf '%s\n' "$WORKING_TREE" | grep -vF "$MY_LOG" | grep -c . || true)
echo "my_log=$MY_LOG_EXISTS bullets=$MY_LOG_BULLETS tree_beyond_log=$TREE_BEYOND_LOG"
echo "--- my commits today ---"; echo "$MY_COMMITS"
echo "--- working tree ---"; echo "$WORKING_TREE"
```

Notes on this block:

- `git log HEAD "$REF"` is the union of both refs, so a commit that reached
  origin from another machine counts even though local `main` has not pulled it
  yet. On a brain with no remote, `REF` is `HEAD` and the duplicate ref is
  harmless.
- `--untracked-files=all` lists every new file individually, for the same
  reason `session-debrief` Step 4 needs it: without it a whole new folder
  collapses to one `?? areas/` line and the grouping in Step 2 has nothing to
  work with.
- `git status --short` wraps any path containing a space in double quotes.
  Treat those quotes as display, not as part of the filename: when a fix
  proposal has to name such a path, quote it properly in the suggested command
  instead of pasting the token through as-is.
- The `$# -eq 0` branch is a fail-closed guard, and it matters more than it
  looks. Without it, an empty flag list leaves `git log` with **no** `--author`
  filter at all, so it returns every commit in the window from everyone, and
  `[orphan commits]` then accuses the operator of undocumented work that is
  actually a teammate's. The parse can come back empty while Block A still
  resolved the operator fine, because the two read the frontmatter differently:
  a registry file with a mistyped key (`git-names:` for `git_names:`) still has
  the `- Name` line that Block A greps for, but no list this parser can find.
  When the guard fires, attribution is **unavailable**, which is not the same
  fact as "no commits today"; the report says so and proposes nothing about it.
  Step 1b carries the same guard for the same reason.
- `TREE_BEYOND_LOG` counts the dirty paths that are *not* today's log. Today's
  log is almost always dirty while this skill runs, because the debrief that
  commits it has not happened yet, so a plain "is the tree clean" test would
  answer "no" on every ordinary day. The `[orphan log]` check needs to know
  whether anything *besides* the log is outstanding, which is what this counts.

### 1b: The teammate window

The window opens on the day of your own previous daily log, because that is the
last day you demonstrably looked at this brain. With no earlier log of your
own, it falls back to 14 days.

```bash
PREV_DAY=$(ls daily-log/ 2>/dev/null \
  | grep -E "^[0-9]{4}-[0-9]{2}-[0-9]{2}-${SLUG}\.md$" \
  | grep -v "^${TODAY}-" | sort | tail -1 | cut -c1-10)
SINCE="${PREV_DAY:-14 days ago}"
echo "window_since=$SINCE"
```

Both forms are handed to git's own date parser (`--since`), which is the only
portable way to express a relative window here: shell date arithmetic
(`date -d`, `date -v`, `date -j`) is not portable and is banned in shipped
commands. The window has **no upper bound**. After two weeks away, `SINCE` is
two weeks ago and the digest is long; that is the correct behaviour, and the
report caps each teammate's rendered commit list at 30 entries with a "+N more"
note rather than shortening the window and hiding the rest.

```bash
LOGS_KNOWN=$( { git ls-tree -r --name-only "$REF" -- daily-log/ 2>/dev/null
                git ls-files -- daily-log/ 2>/dev/null
                git -c core.quotePath=false status --short --untracked-files=all -- daily-log/ \
                  | cut -c4- | sed 's/^"//; s/"$//' ; } | sort -u )
for f in operators/*.md; do
  case "$f" in
    operators/CLAUDE.md|operators/ONBOARDING.md|operators/operator_template.md) continue ;;
  esac
  OSLUG="$(basename "$f" .md)"
  if [ "$OSLUG" = "$SLUG" ]; then continue; fi
  set --
  while IFS= read -r NAME; do
    [ -n "$NAME" ] || continue
    set -- "$@" --author="$NAME"
  done <<YAML
$(awk '/^---$/{if(f)exit;f=1;next} f' "$f" | awk '/^git_names:/{g=1;next} g&&/^[[:space:]]*-[[:space:]]+/{sub(/^[[:space:]]*-[[:space:]]+/,"");print;next} g&&/^[^[:space:]]/{g=0}')
YAML
  if [ "$#" -eq 0 ]; then
    echo "TEAMMATE $OSLUG: no git_names in the registry, nothing to attribute"
    continue
  fi
  echo "TEAMMATE $OSLUG"
  git log "$REF" "$@" --since="$SINCE" --date=short \
    --pretty=format:'C|%h|%ad|%an|%s' --name-only 2>/dev/null
  echo
done
echo "--- logs known to the repo ---"; echo "$LOGS_KNOWN"
```

The registry exclusion list is the same one Block A uses in Step 0, plus your
own file. Each commit prints as one `C|hash|date|author|subject` line followed
by the files it touched, then a blank line. `LOGS_KNOWN` is the union of three
sources: the daily logs committed on `$REF`, the ones tracked locally, and the
ones sitting in the working tree untracked. All three matter for the
`[teammate]` check below. A teammate's log can be on origin while your working
copy is behind, so testing the filesystem alone would report a missing log that
exists; and a log written today has usually not been committed anywhere yet, so
testing the committed tree alone would report the same thing. Note that the
three sources are read through git rather than with a `ls daily-log/*.md`
glob, deliberately: a glob that matches nothing is a fatal error in `zsh` (it
aborts the block, and the redirection does not even hide the message), while
in `bash` it silently passes the unexpanded pattern through. A brand-new brain
with no logs yet hits exactly that case.

`--author` matching is a substring regex over the author name, not an identity
check. Two teammates whose names contain one another (`Sam` and `Sammy`) will
cross-attribute; if that ever happens, the registry can hold the fuller
spelling. It stays a review aid either way.

### 1c: The pull-request queue

```bash
if ! command -v gh >/dev/null 2>&1; then
  echo "GH-UNAVAILABLE: gh is not installed"
elif ! gh auth status >/dev/null 2>&1; then
  echo "GH-UNAVAILABLE: gh is not authenticated"
elif ! PR_JSON="$(gh pr list --state open --json number,title,author,createdAt,reviewDecision 2>&1)"; then
  echo "GH-UNAVAILABLE: gh could not list pull requests for this repository"
  echo "$PR_JSON"
else
  echo "$PR_JSON"
fi
```

All three failure branches are checked separately because they are not the same
thing and only the last one is easy to mistake for success: `gh` can be
installed and authenticated globally and still fail here, because the
repository's remote does not point at a GitHub host at all. Testing the auth
state alone would let that error through as a non-zero exit in the middle of a
read-only audit.

On any `GH-UNAVAILABLE` line the report's pull-request line reads "gh not
available, PR check skipped", with the reason, and no `[open PR]` fix is
proposed. That is the normal state for a brain that has not adopted
`docs/GOVERNANCE.md`, and it is not a finding. An empty result (`[]`) is
different: `gh` worked and there are no open pull requests.

`reviewDecision` is requested because the check below is about *unreviewed*
pull requests, which the other four fields cannot answer. It comes back empty
for a pull request nobody has reviewed yet, `REVIEW_REQUIRED`, `APPROVED`, or
`CHANGES_REQUESTED`.

---

## Step 2: Cross-checks, into numbered fix proposals

Build one numbered list. Every entry has three parts: a **tag** in brackets, a
one-line **finding**, and a **suggestion** the operator can copy and paste or
act on directly. Nothing here runs anything; a suggestion that names a skill
names it, and stops there.

**`[orphan commits]`** if `MY_COMMITS` is non-empty and your log is missing or
has no bullets (`MY_LOG_EXISTS=no`, or `MY_LOG_BULLETS` is 0). Skip this check
entirely when Step 1a printed `REGISTRY:`: with attribution unavailable there is
no evidence either way, and a guess in this direction accuses the operator of
work that may be someone else's. Report the registry problem instead, as its own
line in the My day section, with the fix (correct the `git_names` key in
`operators/<slug>.md`).

- Finding: `N commits today under your name, but daily-log/${TODAY}-${SLUG}.md is missing or has no entries.`
- Suggestion: run `/session-debrief` now to write today's entries retroactively;
  list the commit subjects so the debrief has something to work from. Code with
  no narrative is the gap the daily log exists to close: in three weeks the
  diff will still be there and the reason for it will not.

**`[orphan log]`** if your log has bullets, `MY_COMMITS` is empty, and
`TREE_BEYOND_LOG` is 0 (nothing dirty except possibly the log itself).

- Finding: `N bullets in your log today, no commits under your name, nothing outstanding in the tree beyond the log.`
- Suggestion: verify rather than fix. Usually one of four things, all benign:
  the work was committed on a different day (a session that closed after
  midnight), the entries are notes about something that produced no files (a
  call, a decision), a debrief deferred its push and the commit is on another
  machine, or the log is written and simply not committed yet. A fifth
  possibility, that a write was lost somewhere, is not benign, which is why
  this is worth ten seconds before closing the day.
- This check reads the tree through `TREE_BEYOND_LOG` rather than
  `WORKING_TREE` for the reason given in Step 1a. It can co-fire with
  `[uncommitted]` when the log is the only dirty path; that is not a
  duplicate, it is two readings of the same day, and one `/session-debrief`
  answers both. Present them next to each other when both appear.

**`[uncommitted]`** if `WORKING_TREE` is non-empty. Group the paths first,
using the same heuristic as `session-debrief` Step 4: same folder means same
group, one group per `areas/<name>/` topic, one for a skill directory, one for
root-level docs. Ignore nothing (`daily-log/` and `memory/` paths belong to a
group too here, since this skill is not the one that commits them).

- One entry per group. Finding: `N files uncommitted in <group path>.`
- Suggestion: run `/session-debrief`; its Step 4 proposes exactly this
  grouping. Include a proposed subject per group in the shape
  `<area>: <what this group is>`, so the debrief has a starting point rather
  than a blank line. Say plainly that uncommitted work is work teammates never
  receive.

**`[structure]`** for any new top-level folder that root `CLAUDE.md` does not
mention in its Structure section.

```bash
if [ ! -f CLAUDE.md ]; then
  echo "NO ROOT CLAUDE.md: structure check skipped"
else
STRUCTURE_MENTIONED=$(awk '/^## Structure/{f=1;next} f&&/^## /{exit} f' CLAUDE.md \
  | grep -oE '`[^`]+`' | tr -d '`')
TOP_SEEN=$( { git log HEAD "$REF" --since="$TODAY 00:00:00" --diff-filter=A \
                --name-only --pretty=format: 2>/dev/null
              git -c core.quotePath=false status --short --untracked-files=all | cut -c4- ; } \
            | sed 's/^"//' | grep '/' | sed 's|/.*||' | sort -u )
printf '%s\n' "$TOP_SEEN" | while IFS= read -r t; do
  [ -n "$t" ] || continue
  printf '%s\n' "$STRUCTURE_MENTIONED" | grep -qF "$t/" || echo "UNDOCUMENTED TOP-LEVEL: $t/"
done
fi
```

The candidate folders are iterated with `while IFS= read -r`, not with
`for t in $TOP_SEEN`. Unquoted word splitting is a shell-dependent behaviour:
`bash` splits the multi-line value into one word per folder, `zsh` does not
split it at all and runs the loop body exactly once with every folder glued
into a single value, which then matches nothing and reports one nonsense
finding. Reading line by line behaves the same way in both.

- Finding: `new top-level folder <name>/ is not mentioned in the Structure section of the root CLAUDE.md.`
- Suggestion: the exact line to add, at the end of that section:
  `` - `<name>/`: <one line saying what lives there>. ``
  A `CLAUDE.md` edit is never applied by this skill and never applied without
  its own explicit approval; the proposal is the whole deliverable.

Two caveats to read the output with. The scan takes the *first* path component,
so a new file at the repository root has no folder and is skipped, and the
folder of a renamed file is reported under its old name. And `$TOP_SEEN`
covers today's commits from every author plus the working tree, because an
undocumented folder is a workspace fact, not a personal one.

**`[memory drift]`** from `skills/memory-checkup/SKILL.md` Step 1: run checks
**A** (index rows pointing at missing files), **B** (active files with no index
row), and **D** (frontmatter status against the index-row emoji) exactly as
that file defines them, and do not restate the blocks here. Those three are the
whole-corpus checks that a day's work most often breaks. C and E are left to
`/memory-checkup` itself, which reads the corpus at leisure.

- One entry per finding, keeping the wording the check produced
  (`ORPHAN ROW`, `ORPHAN FILE`, `EMOJI MISMATCH`).
- Suggestion: run `/memory-checkup`, which proposes each fix one at a time and
  writes nothing without approval. Do not propose the edit inline: memory
  changes go through the skill that asks first.

**`[teammate]`** if a teammate has commits on a date inside the window and
`LOGS_KNOWN` holds no `daily-log/<date>-<their-slug>.md`.

- Finding: `<slug> has N commits dated <date> with no daily-log/<date>-<slug>.md in the repo.`
- Suggestion: a message to send them, drafted and ready:

  > You pushed N commits on `<date>` (`<subjects>`) and I cannot find
  > `daily-log/<date>-<slug>.md`. Could you run `/session-debrief` to write
  > that day up retroactively? Not about the code, it looks fine: without the
  > log, whoever picks the thread up next has the diff and none of the reasons.

  Send it or do not; that is the operator's call, and the tone is theirs to
  adjust. Never edit a teammate's log yourself, per `daily-log/CLAUDE.md`.

**`[open PR]`**, only when Step 1c returned data: a pull request whose
`createdAt` date part is strictly earlier than `$TODAY` and whose
`reviewDecision` is empty.

- Comparing `createdAt[0:10]` with `$TODAY` is a string comparison between two
  ISO dates, which sort chronologically. No date command is involved, which is
  exactly why the check is expressed this way.
- Finding: `PR #N ("<title>") by <author>, opened <date>, no review yet.`
- Suggestion: run `/pr-review N`. Note in the report that `/pr-review` is part
  of the governance pack and is inert until the team adopts
  `docs/GOVERNANCE.md`.

If every check comes back empty, the list is empty. Say so plainly; do not
invent a finding to justify the run.

---

## Step 3: Render the report

One file per skill, overwritten each run, no history kept. Delete the previous
copy first: the Write tool refuses to overwrite a file it has not read in this
session, and this path is stable across runs.

```bash
FILE="${TMPDIR:-/tmp}/brain-eod-review.html"
rm -f "$FILE"
```

Write it with the standard template from `skills/html-preview/SKILL.md`, title
"End-of-Day Review". Do not copy the `<style>` block into this file or modify
it; reuse it as it stands there. The content inside `<div class="container">`
follows this order:

1. **Header.** `End-of-Day Review · <today>`, with a meta line carrying the
   counts: log bullets, your commits today, fix proposals, teammates active in
   the window. If `FETCH_NOTE` is non-empty, it goes directly under the header
   as a `.note-block`, before anything else on the page.
2. **Teammates since `<SINCE>`.** One subsection per teammate with activity:
   commit count, then the commits as a compact list. Files under `memory/`
   are called out on their own line above the list, because a changed project
   status is the one thing you most need to know before your own debrief
   writes over it. A teammate with no commits in the window gets one line
   saying so. This section comes before your own day: it is the part you
   cannot know without asking.
3. **My day.** Log bullets, commits, working-tree state in one line, then the
   `[orphan commits]`, `[orphan log]`, and `[uncommitted]` proposals.
4. **Structure and memory.** The `[structure]` and `[memory drift]`
   proposals.
5. **Next step.** A single line, first match wins: working tree dirty means
   `/session-debrief`; else an unreviewed pull request older than a day means
   `/pr-review N`; else "all clean, nothing waiting".
6. **Footer.** `Company Brain`.

Each proposal renders as a `.todo` block, reusing the template's classes:

```html
<div class="todo">
  <div class="todo-check"></div>
  <div class="todo-text">
    <span class="badge badge-watch">[tag]</span>
    <strong>the one-line finding</strong>
    <div class="todo-context"><pre>the suggestion</pre></div>
  </div>
</div>
```

Badges by tag: `[orphan commits]`, `[orphan log]`, and `[uncommitted]` use
`badge-urgent`; `[memory drift]`, `[teammate]`, and `[open PR]` use
`badge-watch`; `[structure]` uses `badge-new`. A section with no proposals says
so in one italic line rather than rendering an empty container.

Open it with the portable open block:

```bash
( open "$FILE" 2>/dev/null || xdg-open "$FILE" 2>/dev/null || start "" "$FILE" 2>/dev/null ) \
  || echo "Open this file in your browser: $FILE"
```

---

## Step 4: Print the fix list in chat

The report is for reading; this is for acting. Print the same proposals as a
flat numbered list, tag first, finding next, suggestion indented under it,
plus the report path so it can be reopened. Close with the single next step
from the report, and with `FETCH_NOTE` if it was set.

With nothing found, say that in one line and give the next step anyway.

Then stop. No follow-up question, no confirmation loop, no offer to apply
anything. The operator applies the fixes, or does not, and closes the day.

---

## Rules

- **Read-only on the work,** apart from the approval-gated friction-log append
  described under Self-improvement below. The only file the audit itself writes
  is `${TMPDIR:-/tmp}/brain-eod-review.html`. It never commits, never edits
  memory or any daily log (including its own operator's), never deletes a
  branch, and never leaves a bookmark behind in the repository. The window in
  Step 1b comes from the previous daily log precisely so that no marker has to
  be written to define it.
- **Never invokes another skill.** `/session-debrief`, `/memory-checkup`, and
  `/pr-review` appear as suggestions in the output and nowhere else. A
  read-only audit that starts writing through another skill is no longer
  read-only.
- **Peer-symmetric.** Any operator runs the same skill and gets the same
  report. There is no privileged reviewer, no operator who is exempt from the
  checks, and no check that only one operator can act on.
- **The report is about the workspace, not about people.** Author attribution
  is a review aid, not a security boundary: git author names are self-declared
  and trivially set to anything. If your team needs enforcement, that is
  branch protection and CODEOWNERS in `docs/GOVERNANCE.md`, not a nightly
  report.
- **Non-blocking.** Every collector degrades to a note: no remote, a failed
  fetch, no `gh`, an unreadable registry entry. The skill finishes and says
  what it could not read.
- **One run, one report.** The temp file is overwritten each time, never
  archived, never committed. `.gitignore` should not need to know it exists,
  because it never lands in the repository.
- **Suggest, never apply.** Including `CLAUDE.md` edits, which need their own
  explicit approval even when a human is the one making them.

## Self-improvement

At the end of the run, check it against these friction triggers: **avoidable
round-trip · improvisation · breakage · token waste · operator correction**
(full definitions in `skills/_improvements/capture.md`). If at least one fired,
ask the operator "there was friction on X, should I log it?"; on their ok,
append an entry to `skills/_improvements/friction-log.md` in the format
`capture.md` defines. Clean run: say nothing. Never self-edit this skill;
improvements go through `/skill-improve`.
