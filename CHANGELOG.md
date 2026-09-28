# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-09-28

### Fixed

- `/session-debrief` no longer reports success when a commit was dropped on the way to `origin/main`: the engine checks by content that every line the local commits added or removed reached origin, and stops with a dedicated outcome (exit 41) when one did not.
- After a push through the temporary worktree, local `main` is left diverged from origin; the engine now reports the divergence, and `/sync` realigns with `reset --keep`, never a rebase, so the next sync raises no spurious conflicts and never regresses teammates' content.
- A conflict during the worktree integration is left standing in the worktree (exit 21), with a procedure to resolve it there, instead of being aborted and deferred.
- Archiving a memory item (a `git mv` into `memory/archive/`) no longer breaks the debrief commit: the engine accepts both halves of a staged rename.
- Skill snippets no longer use positional parameters (`$1`, `$2`), which the skill runner substitutes before the shell sees them: `pr-review`, `session-debrief`, `sync` and `system-checkup` split fields with `cut`, `sed` and `grep`.

### Changed

- The git engine is one script, `scripts/debrief-push.sh`, shared by `/session-debrief` and `/sync` (which delegates with `--integrate-only`); the two inline copies are gone. Files are passed one per argument, never as directories. Rare outcomes moved to `skills/session-debrief/reference/push-outcomes.md`, which the script points at on every non-zero exit.
- The engine refuses to commit when the index already holds staged paths outside the allow-list (exit 4), instead of sweeping another session's work into the debrief commit.
- `scripts/git-locked` serializes git operations between parallel sessions on the same clone.
- Two team options, off by default: `brain.debrief.autoTake` (take origin on a conflicted `daily-log/` or `memory/` file when the local side is a strict subset of it) and `brain.debrief.realign` (`reset --keep` after a worktree push).

### Added

- Tests for every shell script in `scripts/` (`scripts/tests/`): a bench that reproduces the lost-commit scenario, a lock test, and a static check on the skill snippets.
- `scripts/tests/test-safe-abort-guard.sh`: runs the safe-abort block of `push-outcomes.md`, as written, against a rebase stopped on a real conflict, and proves the guard excludes the conflicted path while still stopping on any other unstaged change.
- `skills/_improvements/browser-verification.md`: habits for any visual check of a web page (serve over HTTP, cache busting, a fresh page per screenshot, reveal-on-scroll and tall pages, animations in real time, one browser session per capture series, a mobile pass at 390px and 320px); `html-preview` points at it.

### Memory layer

- Index rows for `reference_*` files move to `memory/REFERENCES.md` and rows
  for archived items to `memory/archive/INDEX.md`; `MEMORY.md` keeps only what
  the briefing needs. Scripts and checks accept the previous inline layout.
- `memory_gate.py`: new `ROW-BUDGET` check (per-row budget derived from the
  auto-load cap); `/session-debrief` runs `BUDGET,ROW-BUDGET` before drafting
  index rows.
- `scripts/salience_sweep.py`: deterministic, read-only salience sweep; the
  three advanced-layer hooks read it instead of recomputing by hand.
- Federated memory roots, opt-in (`docs/ADVANCED.md` section 8): area roots at
  `areas/<name>/memory/`, discovered automatically by every script and skill
  check; one generated index per root; `DUP-ROOT` check; `## Areas` pointer
  rows verified. With no area root, behavior is unchanged.
- `scripts/tests/`: fixture, runner and tests for every script in `scripts/`.

### Governance

- Two tiers of `CLAUDE.md` files: protected system files travel through a feature branch, area files keep landing on `main` through the debrief (`docs/GOVERNANCE.md` step 2, `.github/structural-paths.txt`).
- `/session-debrief` classifies every path before committing (`scripts/classify-paths.sh`) and refuses structural or sensitive paths on `main`, with the split procedures in `skills/session-debrief/reference/split-paths.md`.
- Sensitive paths as an executable recipe: `.github/sensitive-paths.txt`, a local pre-push hook, a CI tripwire that opens an issue, and a `sensitive_owner` flag in the operator registry; no identity is written anywhere but `operators/`.
- Proposal pull requests for non-owners, with a staleness flag; `/pr-review` lists them first and never lets the proposer merge their own.
- `CLAUDE.md` drift scanner (`scripts/check_claudemd.py`) and governance coherence check (`scripts/governance-check.sh`), both run by `/system-checkup`.
- Every script under `scripts/` now ships with a test under `scripts/tests/`.

### Skills suite

- docs: `SKILL-MAINTENANCE.md`, how the skills suite stays small as it learns: reference folders, the measured rule for when a pointer costs more than the text it replaces, incident tables, description trimming, friction-log hygiene, retiring a skill.
- skills: `reference/` subfolders are part of a skill's shape; `system-checkup` moves its zsh note there.
- friction log: entries carry an optional `pattern:` class; open means no `consumed:` line; `skill-improve` counts ownerless entries and routes them; a seed of known failure classes ships in `skills/_improvements/known-patterns.md`.
- session-debrief: the daily log entry records what the session did, not the commit that follows it; one approval gate with an explicit default for a bare "ok"; provenance checked before grouping; co-write rules by file type; the allow-list is composed right before the push, from single files.
- handover: confirms the title before consuming the slot; looks for a hand-written note when the file is missing; no secrets in the file.
- ship: `/ship <branch>` resolves the branch's worktree; on `main` it offers the feature worktrees; a branch with an open PR merges `main` in instead of rebasing.
- daily-briefing: no third-party tool named in the log backstop.
- daily-briefing: on a diverged `main` (ahead and behind), ahead commits are no longer reported as unpushed; patch-identical ones are named as duplicates that drop on realign, and the rest go to `/sync` for a check by content.
- daily-briefing: an open thread is promoted to Today only after checking the state of what it names; a thread closed there is dropped, an unclear one goes to Watch.
- eod-review retired: the teammate digest moves to `daily-briefing`, the unreviewed-PR check to `system-checkup`; the own-day checks are dropped.
- session-debrief: from a feature branch in a linked worktree, only the branch's own work is committed there; the daily log and memory are debriefed from the main tree on `main`, so shared files never fork onto a branch (Step 0 detects the worktree, `scripts/tests/test-debrief-worktree-detect.sh`).
- session-debrief, sync: a refused realignment (`REALIGN-BLOCKED`, or a manual `reset --keep` that refuses) has a written procedure in `push-outcomes.md`, "Realign refused": list the blocking files, release only those already byte-identical to `origin/main` after the operator's ok, report anything else as live work; the engine points at it (`scripts/tests/test-realign-refused.sh`, bench S10).
- meeting-debrief: reads the full transcript, never stopping at an auto-generated summary; every summary point is labelled FACT, HYPOTHESIS or READING; Step 3 names what the meeting confirms, contradicts or adds against memory.
- session-debrief: a project file's Status and Next action are rewritten in place, never appended to, and kept within an index line's budget (detail moves to Updates or the project folder); a recipe for editing a line too long for the Read tool.
- session-debrief: the worktree detection fails closed on a git that lacks `rev-parse --path-format` (older than 2.31): it reads as a worktree and the debrief stops to ask instead of committing shared files onto a branch. README lists git 2.31 or later.
- session-debrief: the allow-list's fresh status lists untracked files one by one (`--untracked-files=all`).
- daily-briefing: the teammate memory digest covers area memory roots as well as `memory/`.
- known patterns: new classes `secret-leak-via-shell`, `shared-tree-commit`, `unverified-fact`, `wrong-environment`, `stale-premise` and `unbounded-fanout`; `non-interactive-shell` gains three sub-patterns (long commands handed to the operator, `pipefail` with an early-exit consumer, batch edits that fail late).
- session-debrief: after a fetch, every file on the allow-list is checked for lines present on both `HEAD` and `origin/main` that the working copy drops; a hit stops the debrief and is shown to the operator, so a stale local copy cannot silently overwrite a teammate's newer edit.
- sparring: when an upstream answer changes, every answer that rested on it is rechecked.
- html-preview: neutral theme (system font stack, white and grey palette, no external font); a reopened fixed-slug preview asks for a hard refresh.
- docs: the "Optional extras" section of `docs/TOOLBELT.md` is removed; the toolbelt lists only external tools the template recommends.

### Constitution

- `CLAUDE.md`: secret values enter through a hidden-prompt script and are never typed into chat or echoed; only variable names are written down.
- `CLAUDE.md`: changes are never left staged in the shared index between steps; stage and commit together.

## [1.0.0] - 2026-08-02

- First public release.
- Skills suite (15 skills: life cycle, governance pack, extras, setup), advanced memory layer (docs/ADVANCED.md, build_index.py, memory_gate.py).
