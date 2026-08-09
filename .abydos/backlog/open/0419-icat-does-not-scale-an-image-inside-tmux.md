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

**Worth checking while there:** whether `abydos-icat` scales at all when it
cannot learn the cell size, or whether it draws 1:1. Refusing with a sentence
naming the reason would be better than a torn picture, and is a smaller change
than making it work.

`Scripts/abydos-icat` is the command; `Sources/AbydosApp/Terminal/` holds the
side that draws it.

---

Its number is where it sits in the queue, not what it is worth doing next.
