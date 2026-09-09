## Context

A terminal scheme is a JSON file with a `terminal` section: a ground, a text
colour, a cursor and sixteen ANSI colours, every one a light/dark pair. Five
ship: `blue` (the default theme), `abydos`, `dracula`, `gray`, and `editor`,
"Editor colours", which states no ground of its own and is drawn on whatever
the editor is wearing. A new installation's terminal *follows the theme*, which
means the theme's own terminal palette — blue's on the blue theme — and falls
back to "Editor colours" only for a theme without one. So the default light
terminal is the blue palette on `#F4F6FB`, and "Editor colours" is a choice. Nothing measured
any of them; the dark half is looked at every day and the light half was not.

## What was measured, 2026-09-09

**The proposal's guess was wrong, and the report was right.** Every scheme
already has a light table of its own — nothing reuses the dark values — and
those light tables are what fail. WCAG 2 contrast of every ANSI colour against
the ground it is drawn on, before any change:

| Scheme | Ground (light) | Under 4.5:1, light | Under 4.5:1, dark |
|---|---|---|---|
| editor ("Editor colours", follows the theme's ground) | each theme's editor: `#FFFFFF` blue, `#FFFBF3` abydos, `#FFFBEB` dracula, `#FDFDFB` gray | **13 of 16**, on every theme | black; bright black; on dracula's `#282A36` also red, yellow, blue, bright red |
| blue (the default theme) | `#F4F6FB` | **13 of 16** | black, red, bright black, bright red |
| gray | `#FBFBF9` | 11 of 16 | black, bright black |
| abydos | `#FDF8EE` | 7 of 16 | black, bright black |
| dracula | `#FFFDF5` | 4 of 16 | black, bright black |

The worst of them: bright green `#8CBF45` at 2.01:1 and bright cyan `#54BDB4`
at 2.09:1 on the blue theme's light ground; "Editor colours"' bright green
`#7FBE55` at 2.15:1 and bright cyan `#4FBAB1` at 2.25:1 on any light ground.
Those are the colours a prompt, a `ls --color` and a `git diff` lean on. The
full list — 98 pairs — is what `TerminalContrastTests` printed before the fix
and is reproducible by reverting the scheme files and running it.

**The shape of the fault.** The light tables were chosen to *look like* the
dark ones — the same hue, a little darker — rather than to read on a
near-white ground. Colours that are bright on `#282935` at 7:1 are bright on
`#F4F6FB` at 2:1: lightness that helps on one ground is exactly what hurts on
the other. The three that never failed in light mode are black, bright black
and bright white, which are dark greys there.

## Decisions

**The floors are WCAG's, and there are two.** 4.5:1 — the floor for body text
— for fourteen of the sixteen; 3:1 — the floor for text meant to recede — for
bright black, which is the dim one: comments, timestamps, the parts of a prompt
that are not the point. Black is exempt: it is the ground's own colour by
convention, and on a dark ground every palette on the machine has it at 1:1.

*Ruled out: 3:1 for the eight normal colours as well.* They are not dim; they
are the default rendering of everything `ls` and `git` colour. The reporter's
sentence was about reading, and 3:1 is the floor for text large enough not to
need reading closely.

*Ruled out: 7:1.* It would recolour the dark tables the maintainer reads every
day for a fault nobody reported there.

**The fix keeps the hue and moves the lightness.** Each failing value keeps its
hue and saturation (HLS) and moves in lightness — darker on a light ground,
lighter on a dark one — in small steps until it clears its floor with a margin
of 0.08 on *every* ground it is drawn on. For "Editor colours" and "WCAG Level AAA" that is
every theme's editor ground, since they follow whichever is in force. The result is written back into the same key of the
same file, so the files still read as they did. 56 values moved: 47 light, 9
dark.

*What this costs in the light theme:* "bright" colours cannot be lighter than
their normal counterparts on a light ground and clear 4.5:1, so the two halves
of each hue end up close — bright yellow `#8E6A10` beside yellow `#916800` on
the blue theme. That is what every light terminal palette does; the bright
half distinguishes itself by weight rather than lightness there.

*And the other side of the same trade, seen in the pictures:* a powerline
prompt paints these colours as *backgrounds* and puts dark text on them. The
branch segment on the blue theme is the palette's yellow, and near-black text
on it went from about 4.7:1 on `#C08A00` to about 2.9:1 on `#916800`; the path
segment, white text on the palette's blue, went the other way, from about
3.9:1 to about 5:1. The two cannot both hold on a near-white ground: a colour
that reads as text there has a luminance under about 0.17, and a colour that
carries near-black text at 4.5:1 needs one over about 0.29. `editor.json`'s
own note had chosen the background side of this and lost the text side, which
is the case that was reported; the light variants of the prompt themes people
use put light text on their segments for exactly this reason. Recorded rather
than solved, because it has no solution in the palette.

*What this costs in the dark theme, said plainly because that is the half in
daily use:*

| Scheme | Colour | Was | Now | Ratio |
|---|---|---|---|---|
| blue | red | `#CC6666` | `#D27878` | 3.88 → 4.59 |
| blue | bright red | `#D54E53` | `#DD7175` | 3.46 → 4.59 |
| blue | bright black | `#666666` | `#757575` | 2.51 → 3.12 |
| editor | red | `#C7756B` | `#CB7F75` | 4.19 → 4.63 (on dracula's ground) |
| editor | yellow | `#B58A2B` | `#B88D2C` | 4.50 → 4.67 |
| editor | blue | `#3592C4` | `#409BCB` | 4.11 → 4.59 |
| editor | bright red | `#E06C60` | `#E17267` | 4.40 → 4.61 |
| editor | bright black | `#5A5D63` | `#71757D` | 2.16 → 3.08 |
| gray | bright black | `#6A6963` | `#706F69` | 2.86 → 3.12 |

Four of the nine are "Editor colours" on the dracula theme's editor ground,
which at `#282A36` is the lightest dark ground and therefore the one the
follows-the-editor palette has to clear. Reverting any of these is a one-line
change to the file and a failing test naming it.

**The test is the claim, and it names the pair.** `SchemeContrast` in the kit
holds the formula, the floors and the walk over a library; the test asserts an
empty list and prints the list when it is not — scheme, half, colour, whose
ground, ratio, floor. A scheme somebody adds later that fails says exactly
where.

*Where the arithmetic lives.* The scheme tests already had a `Contrast` of
their own, kept out of the app on the argument that nothing in the app drew
from it. That stops being true when a scheme file promises a floor the kit
reads, so the formula is in the kit now and the test helper is a name over it:
one number, two callers, no drift.

*Two tests pinned the old state and were updated rather than deleted:* the list
of bundled scheme ids gains the AAA palette, and the test that keeps Ghostty's
sixteen as Ghostty had them now names the three reds the measurement moved, so
a hand that puts the old values back is told what it has undone.

## What the pictures showed

Sixteen driven screenshots, each the same pane: the sixteen ANSI colours as a
line of text apiece, `ls -G`, `git status` and a `git diff`, on a tmux prompt.
Taken from a bundle built with the old scheme files and one with the new, so the
pair for the default is the report and the fix side by side.

- **Blue theme, light, the default palette, before**: yellow and bright
  yellow are pale ochre, bright green is mint, bright cyan is a wash, white is
  a light grey — the four rows of the card have to be leant into, and the
  `??` of an untracked file in yellow is the worst of them. This is what the
  reporter saw.
- **The same, after**: every colour is a colour of text. Yellow is a dark
  ochre, the greens are leaf rather than mint, cyan is teal, white is a
  mid-grey that still reads as "less". The bright half sits close to the
  normal half, as the design said it would; the card still shows sixteen
  distinguishable rows, because hue carries what lightness no longer can.
- **"Editor colours", light, on the blue theme**: the same reading, on white.
- **Dracula, abydos and gray palettes, light**: the same shape — each darker
  in the bright half, readable throughout, and still recognisably itself:
  dracula's purple prompt and vivid red, abydos's amber, gray's restraint.
- **WCAG Level AAA, light**: darker again, and the most legible of the set
  by a distance; the cost is that the card reads as fourteen dark colours and
  two greys, with less to tell a normal from a bright by.
- **Blue theme, dark, before and after**: the same picture to a glance. Red
  is a shade lighter, and the bright-black row — the `90` line, invisible
  before — can now be found. Nothing else moved on the dark ground.
- **WCAG Level AAA, dark**: pastel and bright, every row plain, the prompt's
  blue and orange a little louder than the theme's own.

Not a picture of the release's terminal: the driven run declines to trust the
project, so the strip above the editor is the trust banner, and the tmux status
line is tmux's own green. Neither is the palette's.

## Release note

For `docs/release-notes-<next>.md`, under what somebody would notice:

> **The light theme's terminal can be read.** A user said the light terminal
> could not be used, and measured, they were right: in the default palette
> thirteen of the sixteen ANSI colours were under 4.5:1 against the light
> ground — bright green at 2:1. Every shipped palette's light half is darker
> now, each colour keeping its hue and clearing WCAG's floor for text on every
> ground it is drawn on; in the dark theme nine values moved by a shade, the
> dim grey most, so a comment in a prompt can be found. A test measures every
> scheme on every run and names the colour that falls short. New beside them:
> **WCAG Level AAA**, a terminal palette at 7:1 for anyone who finds 4.5:1
> tiring, in Settings ▸ Terminal colours. A scheme of your own can promise its
> floor with `"floor": 7` and be held to it.

## Open Questions

- Whether a reader in the light theme wants the bright half more distinct from
  the normal half than 4.5:1 on a near-white ground allows. Asked of the
  reporter with the release.
