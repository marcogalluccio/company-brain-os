# Browser verification

> Open before any visual check of a web page or an HTML export: a preview,
> a screenshot, a full-page capture, a mobile pass. These habits apply
> across skills; a skill that renders HTML points here instead of carrying
> its own copy.

Every section is a habit, the reason for it, and what to do instead.

## 1. Serve over HTTP, bust the cache

Pages opened as `file://` behave differently from served ones: relative
scripts, modules and fetches can be blocked, and what renders is not what
ships. For any page you are verifying, serve the folder with a local HTTP
server, started with an explicit directory argument rather than relying on
the working directory of a background shell, and announce the port. A
self-contained document with inline styles and no scripts, such as an
`html-preview` render, can still be opened directly to read.

After an edit, the browser can keep serving the old file or its linked
assets. Reload with a hard refresh, or change the URL (a new filename or a
cache-busting query), before judging a change as missing. Cache before
code: rule it out first. See `preview-cache` in
`skills/_improvements/known-patterns.md`.

## 2. A fresh page per screenshot, absolute paths

A tab used for iteration accumulates state: reloads, emulated media,
injected scripts, scroll position. Take each screenshot from a freshly
opened page or tab. If a capture times out, open a fresh page first
instead of varying the capture parameters.

Save every screenshot to an absolute path outside the repository (a temp
or scratch directory). A relative path may resolve against the automation
tool's own working directory, and images left in the tree end up committed.

## 3. Reveal-on-scroll and very tall pages

Sections that appear on scroll stay hidden in a full-page capture that
never scrolls, and very tall pages can be cut or come out blank without an
error. Before judging a full-page capture, either scroll through the page
so every section has been revealed, or capture a throwaway variant with
reveal animations disabled and the hero at a fixed height. Never judge the
design from a capture where whole sections are missing.

## 4. Animations in real time

Headless captures that advance a virtual clock do not run compositor
animations or animation-frame loops the way a browser does: they produce
false failures and can hide the real bug. Judge any animation in a real
browser at real time, driven by a browser automation tool, sampling
frames at known moments.

## 5. One session per capture series, then stop

Open one browser session for a series of captures and take every pose
inside it (reload, position, capture), rather than a new browser per shot;
close it when the series is done. Only one agent drives a visible browser
at a time, and the brief says how many series are needed. When the
operator says the result is close enough, stop measuring: hand it over for
their judgement, and report anything left unmeasured as unmeasured.

## 6. Mobile first

Every web interface is checked at 390px and at 320px wide before it is
called done or deployed, not only on desktop.

- **No horizontal scroll:** `document.documentElement.scrollWidth <=
  document.documentElement.clientWidth` holds at both widths (`innerWidth`
  includes a vertical scrollbar, so it can hide an overflow).
- **Form inputs at 16px or larger:** smaller text makes iOS Safari zoom the
  page on focus.
- **Pop-ups and dialogs as bottom sheets on mobile:** anchored to the
  bottom, full width, a maximum height with internal scroll, padding for
  the safe area.
- **Tap targets sized for a finger:** around 44px in both directions, with
  space between neighbours.
- **Short display text** that must stay on one line scales with the
  viewport instead of overflowing it.

## Checklist

```
[ ] served over http://localhost, not file:// (pages with scripts or linked assets)
[ ] hard refresh or new URL after the last edit
[ ] each screenshot from a fresh page, saved to an absolute path outside the repo
[ ] full-page capture shows every section (scrolled through, or reveals disabled)
[ ] animations judged in a real browser, at real time
[ ] one browser session for the series, closed at the end
[ ] 390px and 320px: no horizontal scroll
[ ] inputs >= 16px, dialogs as bottom sheets, tap targets ~44px
```
