# Incidents that shaped `system-checkup`

> Open only when reviewing this skill, never when running it. The hot text
> cites a row by its label; the detail lives here. Format per
> `docs/SKILL-MAINTENANCE.md` section 3.

| Label | What happened | Rule that came out of it |
|---|---|---|
| `zsh-loop-lookup` | Observed once, on one setup: a long zsh script with many piped `<pipeline> \| while read; do ...; done` loops intermittently failed to resolve external commands (`basename`, `grep`) for the rest of the run. Not reproduced in bash; cause unknown. | Every loop body in Step 5 extracts fields with one `awk` call or plain parameter expansion instead of a piped `awk \| grep \| sed` chain: fewer forked processes per iteration. If Step 5 ever reports a command not found mid-run, try running the block under bash before treating it as a finding. |
