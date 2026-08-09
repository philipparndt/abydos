# 419. icat does not scale an image inside tmux

`abydos-icat some.png` in a tmux pane draws the image at its full pixel size,
torn across the rows rather than fitted to the pane — the picture runs off to
the right and the rows below it are pushed down. The same command works in a
terminal with no tmux in it, and kitty's own `icat` works inside tmux, so it is
neither the protocol nor tmux refusing to carry it.

**Where to look first, and why it is likely the size and not the picture.** A
graphics protocol placement says how many cells the image should occupy, and
the number of cells is worked out from the pane's size and the cell's size in
pixels. Inside tmux both of those come from somewhere else:

- The pane is not the window. `ioctl(TIOCGWINSZ)` inside tmux answers with the
  pane, but only if tmux is passing it through — and `ws_xpixel`/`ws_ypixel`,
  which is where the cell's pixel size comes from, is exactly the field that is
  commonly zero under tmux. A zero there is the shape of this bug: no pixel
  size means no cells-per-pixel, and code that falls back to "one pixel, one
  cell" draws the image at full size.
- We already know the cell's pixel size by another route.
  `TerminalView.updateCellPixelSize` computes it from the font and the display
  scale and sets it on both the emulator and the pty, precisely so a program
  sizing to the grid gets the real number. Whether that reaches a program
  running *inside* tmux is the question — tmux re-exports its own idea of the
  window size to the programs in its panes.

So the first measurement is not in our code at all: run `stty size` and a
one-liner printing `ws_xpixel`/`ws_ypixel` in a tmux pane and outside one, in
this terminal, and compare. If the pixels are zero inside tmux, that is the
whole bug and the answer is to ask tmux rather than the tty — or to pass the
size in the way kitty's icat does, which is worth reading since it demonstrably
works there.

**The first measurement, taken — and it refutes the theory above.** Measured on
tmux 3.7b, on a pty deliberately given a pixel size (100×40 cells, 800×800
pixels, so a cell is 8×20), with a program in a tmux pane reading `TIOCGWINSZ`
for itself:

| where | rows × cols | ws_xpixel × ws_ypixel | `#{client_cell_width}` |
| --- | --- | --- | --- |
| no tmux, pty carries pixels | 40 × 100 | 800 × 800 | — |
| tmux pane, client pty carries pixels | 39 × 100 | 800 × 780 | 8 × 20 |
| tmux pane, client pty carries none (`script`) | 23 × 80 | 1280 × 736 | 0 × 0 |

`ws_xpixel`/`ws_ypixel` are **not** zero inside tmux. tmux 3.7b scales the
client's pixel size down to the pane exactly (800×780 for the 39 rows it kept
after its own status line), and where the client's pty carries no pixels at all
it invents a 16×32 cell rather than leaving zeros. So the field the theory rests
on is populated on both routes, and the one thing that *is* zero — tmux's own
`#{client_cell_width}` — the script already falls through when it sees.

`abydos-icat` accordingly computes the same size inside a tmux pane as outside
one. A 32×32 pixel image on an 8×20 cell came out `c=4 r=2` in both, which is
right. So the number the script *sends* is not the bug; look at the side that
draws it. Two things are worth measuring before anything else:

- What the Abydos terminal's own pty carries when tmux is attached to it, since
  the tables above used a synthetic pty rather than `TerminalView`. If
  `updateCellPixelSize` has not run by the time tmux reads the size, tmux
  invents 16×32 and every picture is drawn to the wrong grid — which would look
  exactly like this and is not a zero anywhere.
- Whether a `U=1` virtual placement survives tmux at all on our side. The
  placeholder cells are ordinary characters that tmux is free to move, and the
  image is only as big as the cells that carry it, so a terminal that loses the
  row/column diacritics through tmux's own redraw draws something the wrong
  size while the escape it was sent was correct.

**Worth checking while there:** whether `abydos-icat` scales at all when it
cannot learn the cell size, or whether it draws 1:1. Refusing with a sentence
naming the reason would be better than a torn picture, and is a smaller change
than making it work.

`Scripts/abydos-icat` is the command; `Sources/AbydosApp/Terminal/` holds the
side that draws it.

---

**Both measurements taken, and both come back clean — the fault was in neither.**

*What this terminal's own pty carries with tmux attached to it.* A pane 235
columns wide on a 2× display, `updateCellPixelSize` having run:

| where | rows × cols | ws_xpixel × ws_ypixel | cell |
| --- | --- | --- | --- |
| the app's pty, tmux attached to it | 46 × 235 | 3760 × 1748 | 16 × 38 |
| a pane of that tmux | 46 × 235 | 3760 × 1748 | 16 × 38 |
| a pane split in half | 46 × 117 | 1872 × 1748 | 16 × 38 |

and `#{client_cell_width} #{client_cell_height}` is `16 38` to match. So
`updateCellPixelSize` has run well before tmux reads the size — the ordering
holds, nothing invents a 16×32 cell, and the ioctl inside a pane describes the
*pane*, down to a split one.

*Whether a `U=1` virtual placement survives tmux's redraw.* It does, exactly.
Captured from a pty with tmux 3.7b attached, the picture's cells come back
`[U+10EEEE +0305 +0305][U+10EEEE]…` — the first of each row carrying its two
diacritics and the rest bare — which is byte for byte what the script wrote and
what the same capture with no tmux in it contains. tmux paints them a cell at a
time as they arrive, rewinding with CR and repainting the row, so the same row
is written three times over; the grid it leaves is the right one. The transmit
keys arrive intact too, chunking and all.

**The cause is one word in a format string.** `measure_terminal` asked tmux for
`#{window_width} #{window_height}`, which is the whole window however many panes
it is split into. In a split, a picture was fitted to a screen twice the width
it had, ran off the right-hand edge of its pane, and tmux wrapped the cells
carrying it — which is the tearing. Unsplit, a pane *is* the window and every
picture was already correct, which is why this read as tmux breaking the
protocol. Measured in the app's own terminal, split in half: `term 235 cols ->
c=142` for a 4000×3000 picture in a pane 117 wide. With `#{pane_width}
#{pane_height}` it is `term 117 cols -> c=117 rows=36`, and it fits.

---

Its number is where it sits in the queue, not what it is worth doing next.
