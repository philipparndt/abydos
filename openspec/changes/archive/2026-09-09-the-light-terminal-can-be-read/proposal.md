## Why

A user's report, relayed on 2026-09-09: *"Light Mode ist im Terminal nicht zu
gebrauchen. Die Kontraste sind zu niedrig."* The light theme's terminal cannot
be used; the contrast is too low.

Nobody who works on this app uses the light theme, which is how a terminal
palette can ship unreadable: the dark half is looked at every day and the light
half is a set of hex values in a scheme file that is only ever loaded by the
`isLight:` branch of `SchemeTerminal.named`. The maintainer's words with the
report: *"I don't use the light theme, so the first light theme user should
know."* This is that user, and the report is a measurement the dark-theme desk
cannot make.

What was likely from reading — that the light tables reuse the dark values —
turned out to be wrong when measured: every scheme has a light table of its
own, chosen to look like the dark one, and those tables are what fail. The
design has the numbers.

There is no originating `.abydos/backlog` item: this comes from a relayed user
report, 2026-09-09.

## What Changes

- **The light terminal is measured.** Every bundled scheme, in light mode: the
  contrast ratio of each of the sixteen ANSI colours against the light ground,
  by the WCAG formula, in a test that names the pairs under 4.5:1 — so the
  report becomes a list rather than an impression, and so a scheme added later
  is held to it.
- **The light values are chosen for a light ground.** For the schemes that fail,
  light-mode ANSI values of their own rather than the dark set reused; the ones
  that already have a light table stay as they are unless the numbers say
  otherwise.
- **A palette at 7:1, "WCAG Level AAA".** Asked for beside the fix: the
  "Editor colours" hues moved to WCAG's Level AAA floor against every editor
  ground, light and dark, following the editor's ground as "Editor colours" does. A
  scheme file can now say the floor it promises (`terminal.floor`), and the
  measurement holds it to that — so "high contrast" in a title is a claim a
  test checks.
- **A screenshot in each theme** with a prompt, a coloured `ls` and a diff, so
  the next change to a palette can be looked at by somebody who does not use
  the light theme either.

## Capabilities

### Modified Capabilities

- `terminal`: what a cell's colour is expected to be legible against, in both
  halves of a scheme.

## Impact

- **Resources**: the scheme files' `terminal` sections, light half.
- **AbydosKit**: `SchemeTerminal` gains nothing; a test over its light tables.
- **Not decided here**: whether the contrast floor is 4.5:1 or 3:1 for the
  dimmer ANSI colours that are meant to be dim. The design says which and why.
