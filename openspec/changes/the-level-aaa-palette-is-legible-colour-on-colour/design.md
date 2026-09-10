## Context

`SchemeContrast` holds every palette colour to a floor **against the ground** —
the terminal's background, or the editor's for a palette that follows it. The
AAA palette (`wcag-level-aaa.json`, `"follows": "editor", "floor": 7`) is held
to 7:1 there, its dim colour `brightBlack` to 4.5:1, and `black` to nothing,
being the ground's own colour by convention. Every value passes, and the
2026-09-09 change that made it so was right to measure: the default palette had
thirteen of sixteen colours under the floor on the light ground.

What that measurement never asks is what a program paints. A TUI puts one
palette colour *on another*: k9s draws its selected row and its crumbs on a
bright background, tmux its status bar, `git add -p` its hunk headers, `less`
its search matches. The two screenshots of 2026-09-10 are exactly that — a
light blue row and an orange badge, each with grey-blue text that cannot be
read — and computed from the scheme file, the pairs they can be are:

| pair, AAA dark | ratio |
| --- | --- |
| `brightBlack` #8F939A on `brightBlue` #7EBDF7 | **1.54:1** |
| `brightBlack` on `brightYellow` #E8BF6A | **1.78:1** |
| the default foreground at 45% over `brightBlue` (what `dim` draws) | **1.26:1** |
| `black` #2B2D30 on `brightBlue` | 6.91:1 |

**The asymmetry is the whole of it.** A colour has one luminance, and its
contrast against a dark ground and against a light background move in opposite
directions. The ordinary palettes' dim grey sits near luminance 0.13, which is
about 3:1 on the dark ground *and* about 3:1 on a bright blue — balanced,
though nobody chose it for that. Lifting the AAA dim colour to 4.5:1 on the
ground bought 1.5 points there and spent them on every light background a
program paints: 1.5:1 is what is left. No single colour reaches 4.5:1 on both
sides of that gap; the floor for a colour that is drawn on both grounds has to
be the floor that can be kept on both.

Dimming has the same shape, per cell: `dim` is the foreground at 45% alpha over
whatever is behind it, in both renderers. Over the ground that recedes the text,
which is what dim means; over a light background a program painted, it fades
the text *into* that background.

## Decisions

### 1. Measure the pairs a program paints, and hold them to 3:1

`SchemeContrast.paintedShortfalls(in:)`: the **painted pairs** — the text
colours a TUI puts on a coloured background, which are `black`, `brightBlack`,
`white`, `brightWhite` and the default foreground, each on every one of the
sixteen palette colours as a background — held to 3:1, WCAG's floor for text
that may be large or is meant to recede, and the floor a program's own pairing
can reasonably be asked to survive. The full sixteen-by-sixteen table is
printed by the same tool for reading; only the painted pairs are held, because
`red` on `magenta` is a choice nobody made for legibility and a palette cannot
be blamed for it.

*Ruled out: holding every pair.* Sixteen colours cannot all be 3:1 from one
another on one gamut; the check would fail every palette that exists and say
nothing.

### 2. The dim colour is held on both grounds it is drawn on

`floor(for: .brightBlack)` becomes 3:1 whatever the palette promises, and the
painted pairs above hold it to 3:1 on the palette's bright backgrounds as well.
For the AAA dark palette that puts `brightBlack` near luminance 0.13 — about
#6E7379, keeping its hue, the way the 2026-09-09 fix kept hues and moved
lightness — at roughly 3:1 on the ground and 3:1 on `brightBlue`, `brightCyan`
and `brightYellow`. The 7:1 promise stands for the fourteen text colours, which
are text on the ground almost everywhere they appear.

*Ruled out: keeping 4.5:1 on the ground and accepting the badges.* The dim
colour is what TUIs paint on their highlights, so this is the one colour where
the trade cannot be made in the ground's favour. The high-contrast palette's
dim text on the ground reads at 3:1, which is what every ordinary palette's dim
text has always read at; it stops being *worse* than ordinary on a selection.

### 3. Dim never makes a pair worse than the program painted

`TerminalDim.alpha(foreground:background:)` in the Kit: the 45% blend when the
blended text still reaches 3:1 against the cell's background, and no dimming
at all when it would not — the program's own pair is left as it was. Both
renderers ask it per dim cell. The luminance arithmetic is a few
multiplications on the cells that carry `dim`, which on a screen are a
handful. Over the ground nothing changes: 45% of the foreground over the
ground is well above 3:1 on every bundled palette, or the ground check would
already have said so.

*Ruled out: dimming toward the farther extreme instead of not dimming.* It
would draw dim text lighter than the undimmed text beside it on a light
background, which reads as emphasis, the opposite of dim.

### 4. The k9s case is captured, not guessed

Which pair the screenshots are is not known from a picture: the text could be
`brightBlack` on `brightBlue`, or the default foreground dimmed over it, and
the fixes above cover both, but the design should say which. k9s needs a
cluster, so the capture is by hand and first: `tmux pipe-pane -o 'cat >
k9s.bytes'` on a pane about to run k9s, then the SGR sequences around the
selected row read out of the file. Whatever they are becomes the first line of
the driven reproduction.

### 5. Reproduce with painted pairs, and read the colours back

`--terminal-pairs <row>` prints, for each run of cells on a row, the
foreground and background the renderer resolves them to and their ratio — so
the claim is a number per pair and not a picture. A driven run prints the pairs
with `--send-bytes` under the AAA palette and under the default one, before and
after the palette and the dim rule change. A screenshot beside it is for
looking, as before.

## What was measured

*(the runs, once made)*

## Release note

> **The Level AAA palette can be read on what programs paint.** A selected row
> in k9s, a badge, a status bar — anything a program draws on a bright
> background — had grey-blue text under the AAA theme that could barely be
> read. The palette had been held to 7:1 against the ground and never measured
> colour on colour, and the dim grey that reads best on dark is the one that
> vanishes on light blue. The dim colour is balanced across both now, dim text
> is never faded into a background a program painted, and every bundled palette
> is measured on the pairs programs actually use.

## Open Questions

- Whether the light AAA palette has the mirror-image fault — a dim colour
  chosen for the light ground that vanishes on the palette's dark backgrounds.
  The measurement in decision 1 says so on the first run, and the fix is the
  same shape.
