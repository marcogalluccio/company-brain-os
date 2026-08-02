# operators/

The registry of who operates this brain. Every skill and doc that needs to
know "who is running this session" resolves it from here, never from a
guess.

## Schema

One file per operator, named after their slug (e.g. `operators/jane-doe.md`).
Frontmatter:

```yaml
---
slug: <slug, a-z0-9- only>
git_names:
  - <exact `git config user.name` value>
github: <github-username>
role: <free text>
---
```

- `slug`: `[a-z0-9-]` only (no capitals), unique across the registry,
  immutable once created. Other systems key off it: `memory/*` frontmatter
  `owner:` fields and `daily-log/YYYY-MM-DD-<slug>.md` filenames. Renaming a
  slug breaks every file that references it, so don't.
- `git_names`: every exact `git config user.name` value that maps to this
  operator, across every machine they use. A list, not a single string:
  someone with a typo'd identity on one machine adds the typo here rather
  than fixing history.
- `github`: their GitHub username, for collaborator management and
  CODEOWNERS.
- `role`: free text. What they do, in their own words or yours.

## Resolution rule

Quote this identically everywhere it is referenced (docs, skills, scripts):

> Resolve the active operator by matching `git config user.name` against
> every registry file's `git_names`. Exactly one match: proceed. Zero or
> multiple matches: stop and tell the user how to fix their identity or the
> registry. Never guess, never derive a slug from the name itself.

The rule exists because a slug is not a transformation of a name (no
`jane-doe` from `git config user.name` reading "Jane"). It is a value one of
the registry files explicitly claims. If nothing claims it, or more than one
file does, stop and say so rather than guessing.

## Uniqueness constraints

- Two operator files must never share a `slug`.
- Two operator files must never share a `git_names` entry. If they do, the
  resolution rule's "exactly one match" guarantee breaks for that identity,
  and every skill that resolves the operator becomes ambiguous, which is a
  data problem to fix, not something to paper over.

## Adding an operator

1. Copy `operators/operator_template.md` to `operators/<slug>.md` and fill it
   in.
2. Commit and push the new file: it has to be on `main` before they clone, or
   their own registry file won't be there.
3. Add them as a GitHub collaborator on the company repo.
4. Point them at `operators/ONBOARDING.md`.

## Removing an operator

Do not just delete their file. Follow the offboarding checklist in
`docs/GOVERNANCE.md` (access revocation, CODEOWNERS cleanup, memory `owner:`
reassignment, and what stays archived versus reserved).
