---
name: html-preview
description: |
  Universal HTML renderer for any document being produced or reviewed in the
  current session: briefings, drafts, reviews, comparisons, tables, or any
  other structured output that benefits from a visual pass before it ships.
  Use when the operator says: preview, /html-preview, show me, render it,
  open it in the browser. Also used automatically when another skill
  generates a briefing or a report.
---

# HTML Preview

Render whatever is being worked on as a styled HTML page and open it in the
browser. This is the standard visual output across the whole skill suite:
`daily-briefing` and `eod-review` both call it for their reports instead of
carrying their own copy of the template.

Run the steps in order.

---

## Step 1: Identify the content

Take the content currently being produced in the session. It could be a
briefing, a copy draft, a review or comparison, a document being edited, a
table, a list, or any other structured output the operator wants to see
rendered. Decide which of the template's elements fit it: sections for
grouping, tables for structured data, lists for items, `.note-block` for
callouts, `.badge` for status indicators, `.todo` for action items.

## Step 2: Render with the standard template

Wrap the content in the template from Step 3, unmodified. Only the markup
inside `<div class="container">` changes per document; the `<style>` block
never does. When the output is meant to become a visual export (carousel,
poster, slide deck), always show this HTML preview first and iterate before
exporting to PNG or another image format.

## Step 3: Save and open

Derive a short `<slug>` from the document, or the producing skill: lowercase,
hyphenated, e.g. `daily-briefing`, `eod-review`, `event-copy-draft`. An
ad-hoc preview uses a fresh slug per document, so two documents open in the
same session never collide. A recurring report reuses its own fixed slug and
overwrites its previous run; if `Write` refuses to overwrite, delete the old
file first.

Write the file with a quoted heredoc so apostrophes and `$` in the content
stay literal:

```bash
FILE="${TMPDIR:-/tmp}/brain-<slug>.html"
cat > "$FILE" <<'HTML'
<!-- the rendered document, using the template below -->
HTML
```

Open it with the portable open block:

```bash
( open "$FILE" 2>/dev/null || xdg-open "$FILE" 2>/dev/null || start "" "$FILE" 2>/dev/null ) \
  || echo "Open this file in your browser: $FILE"
```

Confirm the path to the operator in chat, whether or not a browser actually
opened.

## The standard template

Every preview uses this exact CSS. Do not modify the style per document; only
the content inside `<div class="container">` changes.

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Company Brain - [Document Title]</title>
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: 'Poppins', sans-serif;
    background: #f5f0e8;
    color: #1a1a1a;
    padding: 32px 24px;
    line-height: 1.7;
  }
  .container { max-width: 780px; margin: 0 auto; }

  /* Header */
  .header { margin-bottom: 32px; padding-bottom: 20px; border-bottom: 2px solid #d4cec2; }
  .header h1 { font-size: 26px; font-weight: 700; color: #111; margin-bottom: 4px; }
  .header .meta { font-size: 13px; color: #888; font-weight: 400; }

  /* Sections */
  .section { margin-bottom: 28px; }
  .section h2 {
    font-size: 16px; font-weight: 700; color: #111;
    text-transform: uppercase; letter-spacing: 1px;
    margin-bottom: 12px; padding-bottom: 6px; border-bottom: 1px solid #d4cec2;
  }

  /* Paragraphs */
  p { font-size: 14px; color: #2a2a2a; margin-bottom: 12px; }

  /* Lists */
  ul { list-style: none; padding: 0; }
  ul li {
    padding: 8px 0; border-bottom: 1px solid #e8e2d8;
    font-size: 14px; color: #2a2a2a;
  }
  ul li:last-child { border-bottom: none; }
  ul li strong { color: #111; font-weight: 600; }

  /* Tables */
  table { width: 100%; border-collapse: collapse; font-size: 13px; margin-top: 4px; }
  th {
    text-align: left; font-weight: 600; color: #555;
    font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px;
    padding: 8px 12px; border-bottom: 2px solid #d4cec2; background: #ece7dd;
  }
  td { padding: 10px 12px; border-bottom: 1px solid #e8e2d8; color: #2a2a2a; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #ece7dd; }

  /* Status badges */
  .badge {
    display: inline-block; padding: 2px 8px; border-radius: 4px;
    font-size: 11px; font-weight: 600;
  }
  .badge-urgent { background: #fce4e4; color: #c0392b; }
  .badge-watch { background: #fef3e2; color: #d68910; }
  .badge-ok { background: #e8f5e9; color: #27ae60; }
  .badge-done { background: #e8e8e8; color: #666; }
  .badge-new { background: #e8eaf6; color: #5c6bc0; }

  /* Checkbox / todo items */
  .todo { display: flex; align-items: flex-start; gap: 10px; padding: 10px 0; border-bottom: 1px solid #e8e2d8; }
  .todo:last-child { border-bottom: none; }
  .todo-check { width: 18px; height: 18px; border: 2px solid #bbb; border-radius: 4px; flex-shrink: 0; margin-top: 2px; }
  .todo-text { font-size: 14px; color: #2a2a2a; }
  .todo-text strong { color: #111; }
  .todo-context { color: #777; font-size: 13px; }

  /* Note blocks */
  .note-block {
    background: #ece7dd; border-radius: 8px; padding: 16px 20px;
    font-size: 13px; color: #444; line-height: 1.6; margin-bottom: 12px;
  }

  /* Code blocks */
  pre {
    background: #ece7dd; border-radius: 8px; padding: 16px 20px;
    font-family: 'JetBrains Mono', 'SF Mono', monospace;
    font-size: 12px; line-height: 1.6; overflow-x: auto; color: #333;
  }

  /* Footer */
  .footer {
    margin-top: 40px; padding-top: 16px; border-top: 1px solid #d4cec2;
    font-size: 11px; color: #aaa; text-align: center;
  }
</style>
</head>
<body>
<div class="container">

  <div class="header">
    <h1>[Document Title]</h1>
    <div class="meta">[Date or context line] &middot; Company Brain</div>
  </div>

  <!-- Content sections go here -->

  <div class="footer">
    Company Brain
  </div>

</div>
</body>
</html>
```

## Rules

- **Always this exact CSS.** No dark themes, no per-document colors, no
  swapping the font. Adapt content, not style; compose new element types from
  the existing classes rather than adding new rules.
- **File path:** `${TMPDIR:-/tmp}/brain-<slug>.html`, where `<slug>` names
  the document or the producing skill. Ad-hoc previews use a fresh slug per
  document; a recurring report may reuse its own fixed slug and overwrite
  its previous run (delete the old file first if a write refuses to
  overwrite).
- **Never store the rendered HTML in the repository.** It is ephemeral,
  regenerated on demand.
- **Auto-open after writing**, using the portable open block above; if none
  of the openers work, print the path so the operator can open it by hand.
- **Real UTF-8 accented characters, never apostrophe substitutes**, in any
  language the content is written in.
- **HTML preview before any PNG or PDF export**, always, for visual content.
- **Title and meta line reflect the document** (e.g. "Daily Briefing",
  "End-of-Day Review", "Event Copy Draft"), the CSS never changes.

## Self-improvement

At the end of the run, check it against these friction triggers: **avoidable
round-trip · improvisation · breakage · token waste · operator correction**
(full definitions in `skills/_improvements/capture.md`). If at least one fired,
ask the operator "there was friction on X, should I log it?"; on their ok,
append an entry to `skills/_improvements/friction-log.md` in the format
`capture.md` defines. Clean run: say nothing. Never self-edit this skill;
improvements go through `/skill-improve`.
