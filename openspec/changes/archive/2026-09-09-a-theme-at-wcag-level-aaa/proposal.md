## Why

The maintainer, 2026-09-09, after the WCAG Level AAA *terminal palette* landed
beside the fix to the light palettes: *"I think we should do it for the whole
theme."* A palette at 7:1 for the terminal leaves the editor beside it at
whatever its theme happens to reach, and somebody who chose the palette because
4.5:1 tires them is reading the editor more than the terminal.

What exists: `the-light-terminal-can-be-read` measured every terminal palette
against its ground, moved the failing values, and added a palette that promises
`"floor": 7` in its file and is held to it by a test. The app half of a scheme
has no such measurement. `BundledSchemeTests` checks a handful of highlight
relations — the current find match outshouts the others, a selection is louder
than an inactive one — and nothing checks that the editor's text, the gutter,
the sidebar or any syntax colour can be read against the ground it is drawn on,
in either half of any theme.

There is no originating `.abydos/backlog` item: this comes from a direct
request, 2026-09-09.

## What Changes

- **The app half is measured too.** For every bundled theme, light and dark:
  each text role against the ground it sits on — `editorText` and every syntax
  kind against `editorBackground`, `gutterText` against the same, `sidebarText`
  and `sidebarHeaderText` against `sidebarBackground`, the git colours against
  the sidebar — at the floor the file promises, 4.5:1 unless it says more. The
  design decides which pairs are text on a ground and which are grounds beside
  grounds, since a highlight behind a selection is not read as text and is
  judged by the tests that already judge it.
- **Every shipped theme clears 4.5:1** where the measurement finds it short,
  the way the palettes were moved: hue kept, lightness moved, the file edited
  in place, the dark tables listed because they are the ones in daily use.
- **A theme at 7:1, "WCAG Level AAA".** A whole scheme file — `app` and
  `terminal` — with `"floor": 7` on both, its colours derived from the blue
  theme's hues at Level AAA against its own grounds, offered in the Theme list
  and following the same light-or-dark switch as the others. The AAA terminal
  palette becomes its terminal half; the standalone palette stays for people
  who want it under another theme.
- **A scheme file promises its floor once**, for both halves, and the README
  says so.

## Capabilities

### Modified Capabilities

- `terminal`: the promised floor covers the app half as well as the terminal's.

### New Capabilities

- `themes`: what a theme's text has to reach against the ground it is drawn
  on, in both halves, and that one shipped theme reaches Level AAA.

## Impact

- **AbydosKit**: `SchemeContrast` walks `SchemeApp` roles and syntax kinds
  beside the terminal's sixteen; `Scheme.read` takes `app.floor`.
- **Resources**: the four theme files' failing values move; a fifth file,
  `wcag-level-aaa.json`, gains an `app` section.
- **Tests**: `TerminalContrastTests` becomes the theme's measurement too, or
  gains a sibling; `BundledSchemeTests`' list of ids grows by one — it did once
  today already.
- **Not decided here**: whether syntax colours, which are read as text but
  chosen for distinctness from each other, are held to the same floor as body
  text or one step down. The design says, from the numbers.
