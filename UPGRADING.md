# Upgrading from the template

This repo started as your own private copy of Company Brain OS, created from the
template with **Use this template**. As the template improves, you can pull those
improvements into your own repo without touching your company's content.

## Step 1: Pull in the template

```bash
git remote add template https://github.com/marcogalluccio/company-brain-os.git 2>/dev/null
git fetch template
git merge template/main --no-commit --allow-unrelated-histories
```

The `--no-commit` flag stages the merge without committing it, so you can sort out
conflicts before anything lands on `main`.

## Step 2: Resolve conflicts by ownership

Start by seeing what actually conflicted:

```bash
git status
```

Everything under "Unmerged paths" needs a decision. The rest of the merge, anything
that applied cleanly, is already staged; leave it alone. Conflicts cluster along a
clear ownership line:

- **Template-owned** (`skills/`, `docs/`, `scripts/`, root meta files like
  `CONTRIBUTING.md`, `LICENSE`): accept theirs. The template maintains these; your
  local edits to them are usually drift, not intent.
- **User content** (`memory/`, `areas/`, `operators/`, `daily-log/`,
  `Company - Context.md`): always keep yours. The template's copies of these are
  generic placeholders and should never overwrite your real content.
- **Mixed ownership, needs a manual read** (root `CLAUDE.md`, `AGENTS.md`,
  `README.md`): these blend template structure with your own customizations, so there
  is no safe default. Open the diff and decide section by section.

Resolve **only the paths `git status` actually listed as conflicted**, one at a time,
never the whole tree at once:

```bash
# for each conflicted path under a template-owned directory or file:
git checkout --theirs -- <path>
git add -- <path>

# for each conflicted path under memory/, areas/, operators/, daily-log/,
# or "Company - Context.md":
git checkout --ours -- <path>
git add -- <path>
```

`git checkout --theirs`/`--ours` with no pathspec, or with a mix of conflicted and
non-conflicted paths, aborts with an error or silently touches files that were never in
conflict. Always name the exact conflicted path. For mixed-ownership files, open them in
an editor, resolve the `<<<<<<<`/`=======`/`>>>>>>>` markers by hand, then `git add` that
file once it's clean.

**Never `git add` a file that still contains conflict markers.** Before you commit,
confirm none remain anywhere in the tree:

```bash
grep -rl "^<<<<<<<" .
```

Empty output means it's safe to continue. Any file listed still has unresolved markers,
even if it's already staged, fix it before moving on.

## Step 3: Review before committing

Run `git status` and `git diff --staged` before you commit the merge. A template
update is still a merge into your production repo; look at what actually changed
before it lands on `main`.

## Step 4: Check the changelog

`CHANGELOG.md` in the template tells you what changed, release to release. Read it
before merging if you want to know what you're pulling in rather than diffing your
way through it blind.
