# Known failure patterns

> Open when logging friction (to tag the entry) or when `/skill-improve`
> groups entries. These are classes of failure seen across skill suites of
> this shape, written as abstractions: no entry here describes a specific
> run. A fresh brain starts with this list so its first friction entries
> have something to be compared against.

How to use it: when a friction trigger fires, check whether the run matches
a class below. If it does, add `pattern: <id>` to the entry (format in
`capture.md`). `/skill-improve` ranks a class shared across skills above a
one-off, and the fix for a shared class is usually one line in every skill
it touches, not a fix in one.

Each class has four parts: what it looks like, why it happens, the habit
that prevents it, and the words that tend to show up in the entry.

## subagent-no-delivery

**Looks like:** a subagent or parallel worker reports "done"; the file it
was supposed to write is missing, truncated, or older than the report. The
parent relays the success, and the gap is found later, by someone else.

**Why:** the report is text, the deliverable is a file, and nothing forces
the two to agree. A worker that hit a permission prompt, a timeout, or an
edit-precondition failure can still produce a confident summary.

**Habit:** every delegation asks for a verification field in the report
(path plus line count, size, or a `grep` the parent can rerun), and the
parent reruns it before relaying. A fan-out of several workers has one
reconciliation step that lists every expected artifact and checks each.

**Entry words:** "reported done", "file missing", "subagent", "never
written", "relayed".

## candidate-fix-not-applied

**Looks like:** a friction entry carries a proposed fix; the next run hits
the same problem; the entry reads as resolved because the fix is written
under it.

**Why:** the log is where the problem was noticed, the skill is where the
fix has to live, and writing the fix down feels like closing it. Nothing in
the log changed the skill.

**Habit:** an entry is open until it carries a `consumed:` line written by
the routine that applied the change. When reviewing, read the skill for the
fix, not the log.

**Entry words:** "again", "same as", "recurrence", "already noted".

## canonical-read-after-options

**Looks like:** the skill points at a canonical file (a template, a
reference deliverable, a style file); the agent proposes options first,
reads the canonical file after the operator has picked one, and the pick
has to be redone against what the file actually says.

**Why:** proposing feels like progress and reading feels like delay, so the
read gets deferred past the point where it could have shaped the options.

**Habit:** the first step of any build procedure is reading the canonical
references it names, before the first option is written. Options are
derived from the reference, not checked against it afterwards.

**Entry words:** "wasted a round", "options", "then read", "template".

## preview-cache

**Looks like:** an HTML preview is reopened after edits and shows the old
version; the operator reviews stale content, or reports a fix as not
applied when it was.

**Why:** the browser caches the file URL. Reopening the same path serves
the cached copy; a linked stylesheet or script keeps its own cache even
when the page itself refreshes.

**Habit:** a reopened preview is never the same URL: a new filename, or a
cache-busting query on the file URL, and say so in chat. Assets linked from
the page need their own bust or a hard refresh. The wider set of browser
habits lives in `skills/_improvements/browser-verification.md`.

**Entry words:** "stale", "old version", "did not refresh", "cache".

## non-interactive-shell

Seven sub-patterns, all born from the same fact: a command run by an agent
has no terminal, no human at the prompt, and no eye on the output; a
command handed to a person crosses a terminal the agent cannot see.

- **Silent no-op.** `sed` and most stream editors exit 0 whether or not the
  pattern matched, so an edit that matched nothing looks identical to one
  that worked. Habit: after any pattern-based edit, `grep` for the new text
  and treat "no match" as failure; for file content, prefer the editor tool
  over stream editing.
- **Nested heredocs.** A heredoc inside a quoted block, or one whose body
  contains its own terminator word, ends early or never; the file written
  is partial and the command exits 0. Habit: write files with the editor
  tool; keep heredocs single-level, single-purpose, with a quoted
  terminator.
- **Interactive prompts in delivered scripts.** A script that calls
  `read -p`, or a tool that opens a login prompt, receives end-of-file when
  run without a terminal and either exits or proceeds with an empty value.
  Habit: parameters through flags or environment variables; a script meant
  for a person to run by hand says so at the top, and the agent never runs
  it.
- **Long foreground processes.** A render, a download, or a watch command
  started in the foreground blocks the turn until it ends, or is killed by
  a timeout that reads as a failure of the command. Habit: start it in the
  background, poll for the artifact, and write the success criterion (the
  file exists, the log says done) before launching.
- **Long commands handed to the operator.** A long one-liner pasted into
  chat for the operator to run gets wrapped by the terminal, and the break
  can land inside a quoted string or a path; part of the command runs, part
  fails, and the output looks like a different bug. Habit: write the
  command into a short script file with the editor tool, check it with
  `bash -n`, save it under a short path with no spaces, make it idempotent
  and have it print its outcome; hand over one line that runs it. Any
  command carrying an absolute path with spaces goes in a script too.
- **`pipefail` with an early-exit consumer.** Under `set -o pipefail`,
  `cmd | grep -q x` can report failure even when the match succeeds,
  depending on timing: `grep` quits on the first hit, and the upstream
  command is killed by `SIGPIPE` or exits with a write error, which fails
  the pipeline. The same holds for `head` and `read`. Habit: capture first (into a variable or a file), then match; a
  check never ends a pipeline with a consumer that stops reading.
- **Batch edit that fails late.** A script that applies several asserted
  replacements and writes the file once at the end discards every edit
  that already worked when a later assertion fails. Habit: write after each
  successful replacement, or make the batch explicitly all-or-nothing and
  say so; then `grep` for the new text either way.

**Entry words:** "exit 0 but", "hung", "waited", "EOF", "heredoc",
"prompt", "line wrapped", "SIGPIPE", "failed but matched", "edits lost".

## destructive-drill-no-standin

**Looks like:** a rehearsal of a destructive operation (a reset, a rebase,
a branch deletion, a migration, a bulk rename) is run against the live
repository or tree "to see what happens"; what happens is that it happens.

**Why:** the operation is being tested precisely because its behaviour is
unclear, and an unclear operation on live data has no undo.

**Habit:** a disposable copy first (a throwaway clone, a temporary
worktree, a copied folder), with the success criterion written down before
the run. The live tree gets the operation only after the drill passed on
the stand-in.

**Entry words:** "just to check", "reset", "lost", "restore", "rehearsal".

## positional-in-snippet

**Looks like:** a shell snippet inside a skill uses `$1` or `$2`, typically
inside an `awk` program; when the skill runs, the field prints empty or the
whole line prints instead.

**Why:** the skill runner substitutes positional parameters in the skill
text with the invocation's own arguments before the shell sees them. The
snippet the shell runs is not the one in the file.

**Habit:** no positional parameters in skill snippets. Split fields with
`cut`, or with `sed -E` and a capture group; if `awk` is unavoidable, pass
values in with `-v` and avoid field references.

**Entry words:** "prints empty", "whole name", "awk", "field".

## edit-precondition

**Looks like:** an edit to a file fails with a message saying the file has
not been read yet, even though its content was just displayed with `cat`,
`git show`, or a diff.

**Why:** the editor tool's precondition is a prior read with the reader
tool in the same session, so it can detect content drift. A shell command
that prints the file does not count, and a read truncated by a size cap
counts only for the part that was read.

**Habit:** read with the reader tool before editing; on a long file, read
the region you are about to edit with an offset, not the whole file.

**Entry words:** "has not been read", "edit failed", "cat".

## relative-date-drift

**Looks like:** "next Thursday" or "in two weeks" written into a log or a
memory file; a weekday computed in the head and wrong; a deadline that
moves every time the file is read.

**Why:** relative dates are correct at the moment of writing and wrong at
every later read; weekday arithmetic done mentally has no check.

**Habit:** absolute ISO dates in anything saved; the weekday of any date
that matters comes from the `date` command, never from arithmetic.

**Entry words:** "wrong day", "next week", "which Thursday".

## secret-leak-via-shell

**Looks like:** a token, key or password shows up in the chat, in the
agent's context, in shell history, or in a saved file: pasted by the
operator on request, passed as a command-line argument, or printed back by
a CLI inside its own error message.

**Why:** the agent's shell and chat are logged, and most CLIs are written
for a human at a terminal: when a credential is rejected they helpfully
repeat it. Writing the secret in safely does not stop it coming back out
through stderr or a service log.

**Habit:** a secret never passes through the agent. It goes into `.env`
through a small script the operator runs in a real terminal: the script
refuses to run without one (`[ -t 0 ]`), reads the value with a hidden
prompt, checks its shape, replaces exactly one anchored line (`^NAME=`)
and refuses if that line is missing or duplicated, sets the file to
`chmod 600`, then prints only a public identifier from a test call, never
the value. Handoffs, logs and
memory store the variable name, not the value. Every authenticated command
pipes stdout and stderr (`2>&1`), and any service log it tails, through a
redaction filter that masks by the secret's shape rather than a list of
known prefixes; the filter is tested on a fake value before it is trusted.
A pipe into the filter hides the command's own exit status unless
`pipefail` is set (and then mind the early-exit consumer case under
`non-interactive-shell`).

**Entry words:** "token in chat", "paste the key", "printed the token",
"rotate", "redact", ".env".

## shared-tree-commit

Two sub-patterns of committing on a tree other sessions or teammates also
write to. Git reports conflicts, not regressions, so both pass silently.

- **Staged changes left in the shared index.** A `git add` or `git mv` is
  staged and then left in the index while other sessions or other work
  continue; another session's commit or debrief trips on the staged path or
  sweeps it into its own commit. Habit: a stage is followed by its commit
  within the same flow (a debrief that archives with `git mv` and commits in
  the same run is fine); otherwise use a plain `mv` until the commit is
  ready.
- **Diffing against HEAD instead of origin.** A local copy older than what
  a teammate already pushed reads as an ordinary modification; it stages
  and commits cleanly and erases the newer edit. Habit: fetch first, then
  read the removed lines of `git diff origin/main -- <file>` and keep only
  those that also exist in `HEAD`: a line on both `HEAD` and `origin/main`
  that the working copy drops, and that this session did not mean to
  remove, is a stale copy (lines only on origin are upstream additions, not
  a hit). On a hit, stop and show the lines to the operator; merge only with
  their approval. After committing, `git diff --diff-filter=D --name-only
  origin/main...HEAD` lists only your side's deletions; check none is
  unexpected.

**Entry words:** "staged", "swept in", "overwrote", "disappeared",
"regression", "older copy".

## unverified-fact

**Looks like:** an amount, a date or a name dictated in conversation goes
into a document as said, and contradicts what memory already records; an
email address, domain or handle is written by analogy with a similar one
and does not exist.

**Why:** a dictated value feels authoritative because the operator said
it, and a plausible address feels verified because it follows a pattern.
Neither was checked against a source.

**Habit:** dictated amounts, dates and names are cross-checked against the
project's memory file before they enter a document; a mismatch is asked
about, not resolved silently. A default that diverges from a written
decision is declared as a divergence. Addresses, domains, handles and
emails are copied from a verified source, never composed.

**Entry words:** "wrong amount", "memory says", "bounced", "does not
exist", "guessed the address".

## wrong-environment

**Looks like:** a command against an external service returns a result
that contradicts what the operator knows; the agent reports it as fact,
and it turns out the command queried a test or staging instance.

**Why:** a local `.env` is development configuration by default. It can
point at a test account, a sandbox, or a stale deployment, and nothing in
the response says which environment answered.

**Habit:** find where the service really runs (the project's deploy notes
or config) and run commands against it from there. When an API result
contradicts what the operator remembers, suspect the environment before
the finding, and name the environment in the report.

**Entry words:** "test account", "staging", "wrong account", "local .env",
"operator says otherwise".

## stale-premise

**Looks like:** a load-bearing decision in a spec or plan changes midway;
work continues on decisions that were derived from the old one, and the
mismatch surfaces only at review or in use.

**Why:** the change is made where it was discussed, and the decisions that
rested on it live elsewhere in the document, each still internally
consistent.

**Habit:** when a load-bearing decision changes, list every decision
derived from it and recheck each premise before continuing. Mark the ones
that no longer hold in the same pass.

**Entry words:** "changed our mind", "no longer true", "based on the old",
"premise".

## unbounded-fanout

**Looks like:** a subagent sent to read through a large archive or run a
long plan spends its budget on the wrong part of it (the oldest material
first, the easy tasks first), or one agent both implements and approves
its own work.

**Why:** a brief without a perimeter leaves the order and the stopping
point to the worker, and a single agent that plans, builds and reviews has
no second view on any of it.

**Habit:** a large read-through gets its perimeter in the prompt: newest
first, a date cutoff, a cap on items before checking back. The parent reads
progress counts mid-run and corrects course early. A plan executed through
subagents keeps roles separate: an orchestrator that assigns and verifies
but does not implement, implementers sized to each task's difficulty, and
a reviewer between tasks that looks for problems before the next task
starts.

**Entry words:** "read everything", "oldest first", "ran out", "no
cutoff", "reviewed its own".
