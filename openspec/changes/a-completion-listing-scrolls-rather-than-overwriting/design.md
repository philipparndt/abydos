## Context

A shell's completion listing is drawn below the prompt. When the prompt is near
the bottom, the shell makes room by scrolling — line feeds at the last row —
then draws the listing and moves back up. The report says the listing lands on
top of what was on the screen instead.

Most people here run every pane inside tmux, and tmux runs the outer terminal
on its *alternate screen*. Our emulator gives the alternate screen a scrollback
of zero (`setAlternateScreen`: `fresh.maximumScrollback = 0`), so a whole-screen
scroll there takes the path in `TerminalScreen.scrollUp` where the retired line
is evicted at once, `discardedLineCount` grows, everything is marked dirty and
the ring is rotated. With tmux's status bar shown, tmux scrolls a *region* one
row short of the screen and never touches that path; with the bar hidden — the
maintainer's setting, `set -g status off` — the region is the whole screen.

## What was measured, 2026-09-09

A driven run with a new verb, `--terminal-screen-at <seconds>`, which prints the
active pane's rows by number and how many lines are above them, so a listing's
place is a fact rather than a picture. The pane is filled with `seq 1 80`, then
`cd`, tab, tab is typed into a project with 120 directories, so the listing is
nine rows and the shell has to scroll to make room for it.

| Engine | tmux | Status bar | Listing | Rows above |
|---|---|---|---|---|
| ours | off | — | 9 rows under the prompt | scrolled into history, `lines-above=72` |
| ours | off, after `less` | — | 9 rows under the prompt | nothing lost |
| ghostty | off | — | 9 rows under the prompt | `lines-above=84` |
| ours | on | shown | 9 rows under the prompt | tmux's own history |
| ghostty | on | hidden | 9 rows under the prompt | tmux's own history |
| **ours** | **on** | **hidden** | **grid: prompt row gone, three listing rows gone, four stale rows of `seq` output above** — in three runs of five | `lines-above=0`, alternate screen |

So the report reproduces in one configuration: the app's own engine, inside
tmux, with tmux's status bar hidden. Intermittent: three fresh sessions out of
five showed it, and the two that did not had an extra event before the typing —
a zoom cycle, or the geometry reporter's timers.

**And the grid and the picture disagreed.** In every run where the grid was
wrong, the screenshot taken two seconds later showed the *correct* screen: the
prompt and all nine rows. Two grid readings 1.3 s apart were identical, so the
grid was not in the middle of changing. When the pane was then forced to
repaint — a presentation-mode toggle, which resizes it and makes tmux redraw
everything — grid and picture agreed again, both correct. So the emulator's
grid held rows the renderer was not showing, and tmux's next full redraw put
them right. What a person sees from that is the report's own words: output
that reads as overwritten, appearing when something repaints — not when the
listing was drawn — and gone by the redraw after that.

## What is named, and what is not

Named: the configuration, the screen (alternate, zero history), and the code
path (`TerminalScreen.scrollUp`, whole-screen region, eviction branch, with the
renderer keyed on absolute line indices through `discardedLineCount` in
`TerminalView+Drawing.swift:110` and `line(at:)`, which does not consult it).
Two of the three mechanisms the proposal listed are ruled out by the table: the
emulator's line feed scrolls at the region's bottom on both engines without
tmux, and the rows the shell is told are the rows the pane draws
(`winsize=18x155` against `rows=18`).

Not named: the exact instruction in that path that leaves the grid and the
renderer's idea of it apart, and why the timing of an unrelated event before
the typing decides whether it happens. That is the next step, with the verb in
hand and the configuration written down; a fix guessed from here would be the
plausible one the proposal warned about.

## Decisions

**Reproduced before fixed, as the proposal asked, and stopped at the named
path rather than at a fix.** The change stays open with 2.1 unticked.

**The verb stays.** `--terminal-screen-at` prints every pane's rows, its
engine, and the lines above, because a report that read a pane other than the
one on screen would call the wrong terminal the screen.

## The instruction, found 2026-09-10

`ScrollbackBuffer.append` at capacity zero — which is what the alternate screen
has, `maximumScrollback = 0` — hands the line straight back without storing it:
`guard capacity > 0 else { return line }`. `scrollUp`'s eviction branch could not
tell that from a real eviction (history full, an old line displaced, every
absolute index shifted by one), so it advanced `discardedLineCount` in both.
The renderer keys its rows on `discardedLineCount` and `line(at:)` does not, so
on a screen with no history the two drifted a row apart on every whole-screen
scroll — the grid holding rows the renderer was not showing until tmux forced a
full redraw, which is the report's "overwritten output that appears on a
repaint and is gone by the next one."

**The fix.** `scrollUp` leaves `discardedLineCount` alone when the scrollback's
capacity is zero: nothing was stored, so nothing shifted, and the document is
only the grid — every row keeps its absolute index `0..<rows` and only its
contents change, which the whole-screen redraw already handles. Real history
still counts a real eviction. `AlternateScreenScrollTests` is the claim: nine
scrolls with no history discard nothing, `line(at:)` matches the grid row for
row, and a screen that does keep history still advances the count on a genuine
eviction.

## Open Questions

None. Whether the reporter runs tmux with the bar hidden no longer matters: the
fix is the code path that failed under it, and it fails under nothing else.

## Release note

> **A completion listing no longer overwrites the output above it.** Under the
> app's own terminal engine inside tmux, a shell's `cd`-tab-tab listing could
> leave stale rows on the screen that only a repaint cleared — the alternate
> screen advanced its count of discarded history on a scroll that discarded
> none, and the renderer drew a row off from where the grid held it. The count
> is left alone where there is no history, and the two agree again.
