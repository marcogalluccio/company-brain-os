# Contributing

Company Brain OS is a template for building organizational second brains. Most teams click **Use this template** to create their own private copy and adapt it to their own domain, culture, and workflows. That is the point. Contributions to improve the template itself are welcome when they make the foundation clearer, more robust, or more useful for everyone adopting it.

## Proposing a change

Open an issue or a pull request describing what you are trying to solve. If it is a feature or structural change, open an issue first so we can discuss whether it belongs in the template or in a fork.

## Guidelines

### Keep the template generic

Contributed files should help any team, regardless of domain, industry, or size. Organization-specific workflows, acronyms, or internal terminology belong in your own company's copy, not the template. Examples and placeholder text should be deliberately neutral.

### Follow the structure

- Memory files go under `memory/` with standardized frontmatter (see `memory/CLAUDE.md`).
- Skills live under `skills/` as self-contained folders with a single `SKILL.md`.
- Areas go under `areas/` with a `CLAUDE.md` (conventions and operational scope) and `Context.md` (content template for customization).
- All structural frontmatter and headers stay in English. Content can be in any language.

### What to include

- Public prose (README, CONTRIBUTING, governance docs): clear, scannable, concrete examples. No em-dashes or double hyphens; use commas, colons, semicolons, or parentheses.
- Skills and areas: include trigger phrases, scope boundaries, and at least one real use-case example that a stranger can follow.
- Files you provide as examples: mark them as deletable so users know they can remove them after learning the pattern.

### What not to commit

- Secrets: API keys, tokens, passwords, `.env` files, credentials.
- Personal data: real names, contact details, private project information, anything not intended for public reading.
- Large binaries: images, videos, archives. Link to external storage instead.
- Generated or local output: build artifacts, editor configs, OS metadata, node_modules, .DS_Store.
- Build tools or CI configuration specific to one team's workflow (general CI patterns are fine).

Not sure if something belongs? Leave it out. Anyone should be able to pick up this template cold and immediately see what it's for and how it's put together.

## Language

Pull requests and issues in English, please. Contributions in other languages are fine in template content (examples, starter areas, comments within skills), but coordinating discussions in English keeps the collaboration readable for everyone.

## Commits

Keep commits focused and include a clear message. Reference issue numbers if applicable. We squash-merge to main.
