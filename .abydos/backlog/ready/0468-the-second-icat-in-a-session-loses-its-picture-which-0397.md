# 468. The second icat in a session loses its picture, which 0397 could not reproduce

0397 closed with one thing it could not make happen and a sentence saying what to
capture if it ever did:

> The three-run sequence in the original report — fine, then space without a
> picture, then neither — was not reproduced here, on this machine, on this
> build. […] If it comes back, the thing to capture is `ABYDOS_TERM_LOG` across
> all three runs and the `c=`/`r=` of each: two different sizes in one session
> would now be a regression rather than the ordinary case.

**It came back.** Reported in the user's own words:

> 0397 is still not fixed. It now works once which is already a step into the
> right direction. But it does degrade and does not work for the second command

with a photograph of four `kitty icat ~/dev/abydos-docs/images/palette.png` in a
row. The first leaves a gap and then **two prompts stacked on consecutive lines**;
the three after it leave neither a picture nor a gap. So the first run does
something the rest do not, which is the half 0397 never saw.

## Start where 0397 said to

Everything below is that item's method and it works; do not invent a new one.

- `ABYDOS_TERM_LOG=<path>` records what the terminal was handed, which is not
  what `script` records — tmux and the line discipline each have a turn first.
- `tmux pipe-pane -o 'cat >> file'` records what `icat` itself wrote, before
  tmux has a turn. That is the other half of the path and it is how the
  column-62 lead was closed.
- **The `c=` and `r=` of every run in one session is the first number to read.**
  0397 proved `icat` derives them from one input only — the pixel size of a cell
  from `TIOCGWINSZ` — and that this app used to answer that question two
  different ways in one pane. Two different sizes across runs is now a
  regression with a name.

## Two leads, from what 0397 changed

**The `SIGWINCH` that 0397 added.** Setting `cellPixelSize` on the pty now writes
the winsize and signals, rather than only doing so when the *grid* changed. That
was the fix — but it means anything that re-sets the cell size mid-session now
resizes the program under it. A first run at one size and every later run at
another is exactly the shape of the report, and this is the newest thing in the
area.

**The stacked prompt.** Two prompts on consecutive lines after run one is not a
picture problem, it is a cursor-position problem: something wrote a prompt, the
picture scrolled, and the shell drew again. 0397 established that `icat` writes
each placeholder row as `\r`, spaces to the left edge, the cells, then `\r\n`.
Where the cursor is when the last row ends decides what the shell does next, and
a picture whose rows scroll off is precisely where that is hard to get right.

## Not the same thing as the picture scrolling

0397 showed that a 988-pixel-high picture at true cell size wants `r=52`, that
`icat` never fits to the pane's height (measured at 47, 20 and 12 rows: `r=52`
every time), and that a picture taller than the pane scrolling away is what kitty
itself does. **That is not this.** This is a first run behaving differently from
the second in the same pane at the same size — and if the sizes turn out to
differ between runs, that is the finding.

## Already ruled out by 0397, with evidence — do not re-run these

The terminal losing the picture; the emulator mis-reading tmux's four-times
placeholder repaint; tmux eating the escapes; the image being evicted (128 MB
budget against 2.9 MB); the transfer being truncated; the prompt erasing it (one
`ESC[J` per capture, at offset 18, tmux clearing on attach). Read that item's
"What was ruled out, with what" before spending an afternoon on any of them.

## Steps

- [ ] Reproduce it — four runs in one pane, in the app, on the current build
- [ ] `ABYDOS_TERM_LOG` and `tmux pipe-pane` across all four, and the `c=`/`r=`
      of each written down here
- [ ] Say what differs between run one and run two, in bytes
- [ ] Account for the two prompts on consecutive lines after run one
- [ ] Fix it, and watch four runs in a row draw four pictures
- [ ] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` says what the project now does
