## Why

The maintainer, 2026-09-10, with two screenshots of k9s under the *WCAG Level
AAA* theme: *"with the Level AAA theme I get a lot of UIs with worse contrast
than before"*. The selected row of the contexts table is light blue with
grey-blue text on it that can barely be read; the `<contexts>` badge is orange
with the same grey-blue text. Both were readable under the palette the theme
replaced.

The AAA palette was measured, and measured carefully — `SchemeContrast` holds
every one of its sixteen colours to 7:1 **against the ground**, the terminal's
own background. That is the right question for a prompt, a listing or a diff,
which is text on the ground, and it is the wrong question for what a TUI
paints: k9s, htop, `git add -p`'s hunks, tmux's status bar, a `less` search
match — all of these put one palette colour *on another*, and no pair of
palette colours was ever measured against each other. Computed from the
scheme file, the pairs the screenshots show:

| pair, AAA dark palette | ratio |
| --- | --- |
| `brightBlack` #8F939A on `brightBlue` #7EBDF7 | **1.54:1** |
| `brightBlack` on `brightYellow` #E8BF6A | **1.78:1** |
| the default foreground dimmed to 45% over `brightBlue` | **1.26:1** |
| `black` #2B2D30 on `brightBlue` | 6.91:1 |
| true black on `brightBlue`, for comparison | 10.51:1 |

The dim colour and the dimming were lifted toward the ground's foreground so
they could be read *on the ground*, which they now can — and that is exactly
what makes them vanish on a light background a program painted, because the
lighter a colour is made to stand out on dark, the closer it sits to the light
backgrounds the same program uses for a selection or a badge. A colour cannot
reach 7:1 against a dark ground and against light blue at once; a palette that
promises AAA has to say which pairs it promises it for, and the program's own
`black` on `brightBlue` shows the pair can be made to work when the darkest
colour is dark.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-10.

## What Changes

- **Measure colour on colour.** `SchemeContrast` gains the pairs a TUI paints
  — every palette colour as text on every palette colour as ground, and the
  dimmed default foreground on each — and a scheme file may say which pairs it
  holds to what. The AAA file's shortfalls are printed first, so the fix is
  aimed at numbers and not at a screenshot.
- **Fix the AAA palette where it fails.** Most likely `brightBlack` darker
  than the ground's foreground would allow on its own and `black` truly dark,
  so that a program's "dim on a light selection" and "black on a badge" are
  read; decided against the table, and against the ground floor the palette
  already keeps.
- **Dimming that respects the ground it lands on.** `dim` is an alpha today —
  the foreground faded toward whatever is behind it — which on a coloured
  background fades the text *into* that background. Whether dim should instead
  pick a colour with contrast against the actual background is decided in the
  design, with the k9s rows as the case.
- **Reproduce with a script, not with k9s.** A driven run prints the SGR
  sequences the screenshots came from — reverse video, `brightBlack` on
  `brightBlue`, dim text on `brightYellow` — under the AAA palette and the one
  before it, and reads the cell colours back, so the before and after are
  ratios.

## Capabilities

### Modified Capabilities

- `terminal`: what a palette is held to — on the ground, and now colour on
  colour — and what dim means on a coloured background.

## Impact

- **AbydosKit**: `SchemeContrast`, the pair measurement and the scheme file's
  way of declaring what it holds; `Schemes/wcag-level-aaa.json`.
- **AbydosApp**: `TerminalPalette.dimAmount` and where dim is applied in both
  renderers, if dim changes.
- **Driving**: a step that paints the pairs and reads the ratios back.
