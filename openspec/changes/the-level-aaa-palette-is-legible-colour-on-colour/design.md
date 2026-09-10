## Context

`SchemeContrast` holds every palette colour to a floor **against the ground** —
the terminal's background, or the editor's for a palette that follows it. The
AAA palette (`wcag-level-aaa.json`, `"follows": "editor", "floor": 7`) is held
to 7:1 there, its dim colour `brightBlack` to 4.5:1, and every value passes.
What that measurement never asks is what a program paints: k9s draws its
selected row and its crumbs on a coloured background, and the two screenshots
of 2026-09-10 show that row and that crumb with grey-blue text nobody could
read.

**The proposal guessed at the pair, and the guess was wrong.** It read the
grey-blue as the palette's dim colour on a bright background, or the default
foreground dimmed over one, and both of those pairs are indeed under 2:1 in
the AAA palette. Neither is what k9s painted. The bytes say what it painted,
and the pane's own cells say what that became.

## What was measured, 2026-09-10

**What k9s sends.** k9s started against a scratch kubeconfig whose servers do
not exist, its config directory pointed at a scratch copy of the maintainer's
(skin `transparent`, as the screenshots), inside a tmux server of the run's
own with `pipe-pane` writing every byte to a file, and `:ctx` opened. No
cluster was reached and nothing of the maintainer's was touched. Around the
selected row and the crumb:

    ESC[38;2;0;0;0;48;2;0;255;255m ESC[1m k3c-almplus(*)   — true black on true aqua, bold
    ESC[38;2;0;0;0;48;2;255;165;0m ESC[1m <contexts>       — true black on true orange, bold

Black on aqua is 19:1. The palette is not in these bytes at all.

**What the pane held.** The same k9s inside a driven pane, read with
`--terminal-pairs 9`, which prints each run of cells with the colours it holds
and the colours it is drawn in:

| | cell holds | drawn | ratio |
| --- | --- | --- | --- |
| before | `indexed(0)` bold on `indexed(14)` | `brightBlack` on bright cyan | **2.86:1** (this run's palette); 1.54:1 under AAA |
| after | `indexed(0)` bold on `indexed(14)` | `black` on bright cyan | **9.73:1** |

Two things happened to k9s's bytes on the way in. **tmux downgraded them**:
the pane runs inside tmux, which knew the outer terminal as `xterm-256color`
and turned 24-bit black and aqua into ANSI black and bright cyan, indices 0 and
14. **Then the bold rule brightened the black**: bold on one of the first eight
colours has meant "the bright twin" since xterm, so index 0 became index 8,
`brightBlack` — the palette's dim grey, drawn on bright cyan. Under the palette
before, that grey was dark and the row was merely dull; under AAA the grey had
been lifted to read on the dark ground, and 1.54:1 is what was left of it on
cyan. The palette is where the fault became visible, not where it lives.

**The painted pairs of every bundled palette**, dark half, black, brightBlack,
white and brightWhite as text on each of the sixteen as background, at 3:1:
every palette fails thirty to forty-two of them, all in two families. Light
text on a base colour fails everywhere — a palette whose base six can be read
as text on dark has made them light, and white on light is not a pair one
colour can rescue. The dim colour on any colour fails everywhere, at 1.5:1 to
2.9:1, for the mirror of the same reason. **Dark text on a painted colour
passes everywhere**, and it is what k9s and every TUI highlight paints.

## Decisions

### 1. Bold brightens a base colour on the ground only

`TerminalAttributes.brightensBold`, in the Kit: bold, a foreground among the
first eight, and the **default background**. A program that pairs black text
with an aqua background chose both, and the terminal keeps out of it; a prompt
that writes bold blue on the ground keeps the bright blue it has always had.
Both renderers ask the predicate where they used to ask `bold`. This is the
fix for the report — 2.86:1 to 9.73:1 on the row k9s paints, with the cells
arriving exactly as they did before.

*Ruled out: bold never brightening, as Ghostty defaults.* It is the cleaner
rule and it changes every prompt on the machine for a fault that is only on
painted backgrounds; the narrower rule fixes what was reported and moves
nothing else.

### 2. tmux is told the terminal shows true colour

`-T RGB` on the tmux client this app starts (`TmuxMirror.attachArguments`), so
a program's 24-bit colours arrive as 24-bit. Verified: `#{client_termfeatures}`
in the pane reads `…,RGB,…` and a `38;2;255;0;0` from the shell arrives as
`rgb(#FF0000)`. `COLORTERM=truecolor` in the pane's environment had not
persuaded tmux on its own. k9s's colours still arrive indexed in the pane —
that is tcell's own choice under `TERM=tmux-256color`, not tmux's downgrade —
which is why decision 1 and not this one is the fix; this one is so that a
program which does send true colour gets it drawn.

### 3. Dark text on a painted colour is measured and held

`SchemeContrast.paintedShortfalls`: `black` as text on each of the fourteen
colours a program paints as a highlight, the dark half, held to 3:1 and named
when under. `pairTable` prints all two hundred and forty pairs of a palette for
reading. *Ruled out: holding every pair, or the dim colour on colour.* Every
bundled palette fails those and none could pass; a floor nothing can reach is
not a floor. *Ruled out: the light half.* Its bright colours are dark so they
can be read on white, and black on them is 1.9:1 — a fault of a different shape
that no single colour fixes, filed below.

### 4. The AAA dim colour stays where it is, and the option is written down

The proposal's asymmetry is real: `brightBlack` at 5.5:1 on the ground is
1.54:1 on bright blue, and a balanced grey (#63676F) would be 3.0:1 on the
ground and 2.84:1 on the worst bright colour. It was not moved. The reported
row never involved it once bold stopped brightening, dim text on a bright
selection is a pair the table shows no palette on the machine survives, and
lowering a palette's headline promise for an unproven case is the maintainer's
call — made with the number beside it.

### 5. Dim is not changed

The proposal asked whether `dim` — 45% of the foreground over whatever is
behind it — should refuse to fade text into a painted background. The
measured case did not involve dim, and a rule written for a case nobody has
seen is the kind this house does not write. *Dropped*, with the arithmetic in
the proposal for when a case arrives.

## Release note

> **A TUI's highlights can be read under every palette.** k9s's selected row
> and its crumbs, a status bar, a badge — dark text a program paints on a
> bright colour — came out grey under the Level AAA theme and dull under the
> others, because bold has brightened the first eight colours since xterm and
> did so on a painted background too, turning the program's black into the
> palette's dim grey. Bold brightens on the ground only now, and tmux is told
> outright that this terminal shows true colour, so a program's own colours
> arrive as it sent them.

## Open Questions

- The light halves: black on bright cyan is 1.9:1 in the light AAA palette,
  because its bright colours are dark so they can be read on white, and a TUI
  that paints black on aqua is unreadable there under every light palette on
  the machine. That is a palette shape and not one colour; its own change.
