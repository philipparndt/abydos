# 397. kitty's own icat works once, then degrades

Two causes fixed in 8efac01: SGR `38:2:r:g:b` written with colons was not
read, so the placeholder cells carried no image id; and the APC cap of 8192
bytes truncated kitty's 131072-byte chunks, so the PNG never decoded. A
single run draws.

**Still wrong on repeat.** First run fine; the second shows the picture and
loses it while still reserving the space; the third blinks and does not even
reserve the space.

Established:

- The stream is not the variable. Three consecutive runs captured from a live
  terminal are structurally identical — `a=T,q=2,f=100,m=1,U=1,s=732,v=988,
  X=2,c=46,r=26,i=<different each time>` and a second chunk. No delete
  commands, no reused ids.
- The emulator handles all three. Replaying the captures back to back gives
  images 1,2,3 and virtual placements 1,2,3, with the placeholder cells
  resolving to 26, 39 and 39 placements — the drop accounting for rows
  scrolled off a 40-row screen.
- `ABYDOS_TERM_LOG=<path>` (e42eb08) records what the terminal was actually
  handed, which is not what `script` records: tmux and the line discipline
  both have a turn in between. A 715 KB capture of three runs shows all six
  graphics commands arriving intact, 22448 placeholder cells (tmux re-emits
  them on every repaint, which is the mechanism working), and only three
  `ESC[J` in the whole stream — so "the prompt erases the picture" is out.

**The open lead:** every placeholder row lands at screen column 62, not
column 0. 62 is exactly the width of the prompt on that line, and the drawn
images are visibly pushed that far right. The rows are separated in the
stream by `\r\n` and then padding spaces out to column 62, which is tmux
repainting content that genuinely sits there — so the offset originates
before this terminal, in what tmux believes about the cursor.

An image pushed 62 columns right is an image whose right-hand columns fall
off the pane, which is also what "images are cut off" looks like.

---

Previously numbered 50, 385.

---

## What column 62 was

Not the cursor, and not ours. kitty's `icat` **centres the picture**:
`--align` defaults to `center`, and each placeholder row is written as `\r`,
then spaces out to the left edge of the picture, then the cells, then `\r\n`.
tmux was repainting exactly what it had been given.

Read off `icat`'s own bytes rather than inferred — `tmux pipe-pane -o 'cat >>
file'` records what the program wrote to the pane, before tmux has a turn,
which is the half of the path `ABYDOS_TERM_LOG` cannot see. In a 185-column
pane the indent is 69 on all 31 rows, and 69 = (185 − 46) / 2. In this app's
194-column pane it is 74 = (194 − 46) / 2. The 62 in the capture above is
(170 − 46) / 2, so the pane it was taken in was 170 columns wide.

So the lead is closed, and it closes nothing else with it: a centred picture
is by construction inside the pane, so this is not what "images are cut off"
is either. That symptom needs its own evidence and does not have any yet.

## What the picture's size turned out to be

The user's reproduction is theirs, and worth keeping in their words:

> `kitty icat ~/dev/abydos-docs/images/palette.png` shows the image and then
> directly removes it again.

`icat` works out how many cells a picture needs from one number and one
number only: the pixel size of a cell, which it reads out of `TIOCGWINSZ`.
This app was giving two different answers to that in the same pane.

`TerminalView.updateCellPixelSize` measures a cell in points and multiplies
by the display's scale, `window?.backingScaleFactor ?? 2`. Cells are measured
when the font is set, which is long before the view is in a window — so the
first answer was always the fallback, a flat 2. This machine's only display
is 1920×1080 at scale 1, where a cell is 8×19 pixels and not 16×38, so the
first answer was wrong by a factor of two in each direction.

The second half is what made it stick. A winsize is one structure holding
cells *and* pixels, and the only thing that ever wrote it was
`recomputeGridSize`, which returns early unless the number of *cells*
changed. So a pane that learnt its real cell size after the window appeared
kept the program on the old number indefinitely — until something else
resized the pane, at which point the true one went out and the same command
started producing a picture twice as large.

Measured, on `palette.png` (732×988), in this app's pane:

- told 16×38, `icat` asks for `c=46,r=26` — half size, and it fits.
- told 8×19, `icat` asks for `c=92,r=52` — natural size, and 52 rows do not
  fit in a 47-row pane, let alone a panel somebody has left at its usual
  height. It is written, it scrolls as it is written, and the prompt lands
  under it. That is "shows the image and then directly removes it again".

The entry's own capture says `c=46,r=26`, which is the first of those: taken
in a pane that had not been resized since the window came up.

Fixed both ways round. The scale falls back to the screen's rather than to
two, so the first answer is right on either kind of display; and setting
`cellPixelSize` on the pty now writes the winsize and sends `SIGWINCH`, so a
change reaches the program whether or not the grid changed with it.

`icat` never fits a picture to the height of the pane — measured, by running
it under a pty of a chosen size: at 47, 20 and 12 rows it asks for `r=52`
every time. So on a 1080-pixel-high screen a 988-pixel-high picture is taller
than any terminal panel, and it scrolls. That is what kitty itself does, and
the way to see all of one is to say so — `kitty icat -h 20 <file>`. The app
lying about the cell size is what used to hide it.

## What was ruled out, with what

Everything below was watched in the app on the current build, driven by
`--terminal --run` with `ABYDOS_TERM_LOG` recording the pane and either
`--screenshot` or `--metal-shot` for what was drawn.

- **The terminal loses the picture.** It does not. One run, three runs back
  to back, a panel too short to hold the picture, and a full tmux repaint
  after a window switch away and back: the picture is drawn each time and
  stays. `images/icat-at-natural-size.png` is one of them.
- **The emulator mis-reads the repaint.** It does not. tmux re-emits each
  placeholder cell four times — the character, `BS`, the character with one
  diacritic, `BS`, with two, `BS`, with three — and replaying a live capture
  through the emulator gives one image, one virtual placement, 26 rows of
  runs and 26 placements built, at column 74.
- **tmux is eating the escapes.** It is not. The graphics commands arrive
  unwrapped, which is tmux having unwrapped `icat`'s own passthrough, which
  needs `allow-passthrough on` — which the session gets as it is attached.
- **The image is evicted.** It cannot be: eviction counts a virtual placement
  as shown, and the budget is 128 MB against a 2.9 MB picture.
- **The transfer is truncated.** It is not. `icat` sends the whole PNG in two
  chunks, the second carrying `a=T,q=2` and no `m` — which reads as the last
  chunk, and the receiver treats it as the continuation it is.
- **The prompt erases it.** Already out, and still out: one `ESC[J` in each
  capture, at offset 18, which is tmux clearing on attach.

## What is still not shown

The three-run sequence in the original report — fine, then space without a
picture, then neither — was not reproduced here, on this machine, on this
build. The size story above accounts for a picture that is drawn and
immediately scrolls away, and for the same command behaving differently
before and after something resized the pane, which is the title. It does not
account for a *second* run losing its picture while a *first* keeps one at
the same size, and nothing here demonstrates that happening. If it comes
back, the thing to capture is `ABYDOS_TERM_LOG` across all three runs and the
`c=`/`r=` of each: two different sizes in one session would now be a
regression rather than the ordinary case.

## Steps

- [x] Read `icat`'s own bytes, before tmux, with `tmux pipe-pane`
- [x] Say what the column-62 offset is: `--align=center`, `(columns − c) / 2`
- [x] Reproduce the user's command in the app and watch what is drawn
- [x] Replay the capture through the emulator and count what resolves
- [x] Rule out the repaint, the eviction, the truncation and the erase
- [x] Find why the same file comes out at two different sizes
- [x] Report the cell size from the screen rather than assuming Retina
- [x] Write the winsize when the cell size changes, not only when the grid does
- [x] Tests that fail on the old answer
- [x] Write down here what was ruled out on the way
- [x] `spec/terminal.md` says what the project now does
