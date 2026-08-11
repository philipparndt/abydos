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

## The pane is not tmux, and that is the whole item

Everything below this heading and above "What four runs measure" was written
before the user said the one thing that mattered:

> I am currently not using tmux for this, it is working in tmux right now.

Every measurement in 0397 and in the first pass on this item was taken **inside
tmux** — the captures came through `tmux pipe-pane`, and 0397's 22,448
placeholder cells were tmux re-emitting them. A plain Local pane had never been
measured, and it is a different protocol. That is why two careful
investigations both concluded it works.

The user's recipe, which they say reproduces every time:

1.  In a plain (non-tmux) Local pane, press Return until about 80% of the
    screen is filled.
2.  `kitty icat ~/dev/abydos-docs/images/palette.png`.

The space is reserved and no picture is drawn — the state the original 0397
report described and neither investigation could produce.

See **"What `icat` writes when there is no tmux"** and **"What it turned out to
be"** below. The two sections above are kept as they were written, because what
they say about the tmux path is true; they are simply about the other path.

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

## Estimate

2026-08-11 15:13 — just picked up again with the user's recipe; a few hours

## What four runs measure, on build 937

Six sessions in the app, driven by `--terminal` with `ABYDOS_TERM_LOG` on the
pane and `tmux pipe-pane -o` on `icat`'s own side, four `kitty icat
~/dev/abydos-docs/images/palette.png` in each. The numbers 0397 asked for:

    run 1  a=T,q=2,f=100,m=1,U=1,s=732,v=988,X=2,c=46,r=26,i=2071036375
    run 2  a=T,q=2,f=100,m=1,U=1,s=732,v=988,X=2,c=46,r=26,i=1706439561
    run 3  a=T,q=2,f=100,m=1,U=1,s=732,v=988,X=2,c=46,r=26,i=4089325352
    run 4  a=T,q=2,f=100,m=1,U=1,s=732,v=988,X=2,c=46,r=26,i=1393558142

**`c=46,r=26` on every run of every session.** One size in one pane, which is
what 0397 said would have to be true for this not to be the size regression
again — so it is not that. The id is fresh each time and no run sends a
delete.

### What differs between run one and run two, in bytes

Not the command, and not `icat`'s own output: 180 KB either side, byte for
byte the same but for the id and the terminal-width padding. What differs is
one thing, and it is tmux rather than `icat`:

- **run 1 does not scroll, run 2 does.** In a 33-row pane the cursor after run
  one is at row 29 and `history_size` is 1; after run two it is at row 32 and
  `history_size` is 26; runs three and four add 28 each. 2 prompt rows + 26
  picture rows = 28, so the first picture is the only one that fits under a
  prompt without pushing anything off the top.
- The terminal is handed 251 KB for run 1 and 221 KB for run 2 — the
  difference is tmux's repaint, not the picture.
- Three `ESC[J` in a whole four-run capture, at offsets 18, 2944 and 213538:
  tmux clearing on attach, exactly as 0397 measured. `icat` writes four (one
  per prompt) and tmux swallows them.

### It draws, on this machine, six times over

`--metal-shot` and `--screenshot` after the fourth run, at 33 rows, at 16 and
at 15, GPU rendering off and on, eight seconds apart and 1.2 seconds apart:
**four runs draw four pictures every time.** Replaying the captures through
the emulator offline agrees — after each run every placeholder run resolves
and no placement is missing its image:

    after run 1: images=1 virtual=1 runs=26 placements=26 withoutImage=0
    after run 2: images=2 virtual=2 runs=28 placements=28 withoutImage=0
    after run 3: images=3 virtual=3 runs=28 placements=28 withoutImage=0
    after run 4: images=4 virtual=4 runs=29 placements=29 withoutImage=0

### What the two prompts on consecutive lines are made of

Read off `icat`'s own bytes rather than guessed at. After the last placeholder
row `icat` writes `ESC[39m CR LF`, and then **zsh** writes its partial-line
mark: `ESC[1m ESC[7m % ESC[27m ESC[1m ESC[0m`, then spaces out to the width of
the terminal, then `CR SP CR`, then `ESC[J`, then the prompt. That is
`PROMPT_SP`, and it is one whole line wide — `%` plus `COLUMNS − 1` spaces.

So there are always two things drawn between the picture and the prompt, and
whether the second lands on the prompt's own line or one above it is decided
by whether that padded line wrapped. It wraps whenever zsh's `COLUMNS` is
larger than the width the pane really has. In every capture taken here the two
agreed — `widthOK=yes`, and `icat`'s own centring indent came to
`(155 − 46) / 2 = 54` on all 26 rows, which is the same arithmetic 0397 closed
column 62 with — so the mark was always erased and one prompt was drawn. **A
pane whose real width is narrower than the program believes is what would
leave the extra line**, and that is now something a running app can be asked
about rather than reasoned about (see the instrument below).

## What was ruled out, with what

All of it on build 937/938, in the app, driven by `--terminal` with
`ABYDOS_TERM_LOG` on the pane and `tmux pipe-pane -o` on `icat`'s side, and
either `--metal-shot` or `--screenshot` for what was drawn. Eight sessions.

- **The size regression 0397 named.** Not this. `c=46,r=26` on every run of
  every session, and `--report-geometry` now prints the winsize the kernel
  holds — `winsize=39x153 pixels=1482x2448 ptyCell=16x38` — which is the same
  before and after every run. There is no second answer to find: nothing
  between two commands typed in one pane re-measures a cell, because that only
  happens when the font or the display changes.
- **The `SIGWINCH` 0397 added, firing mid-session.** It cannot: the cell size
  is worked out in `updateMetrics` and in `viewDidMoveToWindow` and nowhere
  else, and `cellPixelSize` only writes and signals when the value actually
  differs. It *did* have one hole, which is fixed here — see below.
- **The picture being taller than the pane.** Tested at 33 rows (it fits), at
  16 and at 15 (it does not, and 15 rows of it are shown). Both draw. What
  differs between run one and run two is only that run one does not scroll.
- **GPU rendering.** The user has `terminalGPURendering` on and the default is
  off, so this was the one settings difference found by reading their domain.
  Turned on, four runs still draw four pictures.
- **Typing them quickly.** 1.2 seconds apart, so tmux is still repainting run
  *n* when run *n+1* starts: four pictures.
- **The build.** The installed app is 927, from `985b916+`, and 043ff4a — the
  commit that fixed 0397 — is an ancestor of it. The user is on a build with
  the fix; this is not an old binary.
- **Two displays with different scales.** Both are scale 2 (`EV2740X` and
  `DELL U2723QE`, 1920×1080 at 2), so nothing changes when the window moves.
- **A second tmux client, which does change the pane's size.** Real and
  reproduced: attaching a 45-row client to a session the app is showing at 39
  rows resizes the pane to 45 under the app, and the app then shows the top 39
  rows of it. This happens on this machine unbidden — a stray `Abydos` launch
  with no `--open` restores the last project and attaches a second client to
  the same session, which happened twice in one afternoon here. It is a good
  account of "no picture and no gap", because everything tmux draws below the
  app's last row is invisible. It is **not** shown to be the user's cause: the
  four runs still drew with a second client attached, and the shot at the end
  was taken after it had gone.

## What `icat` writes when there is no tmux

The one thing nobody had measured. `icat` under a plain pty of 39×153 with
`TMUX` unset, its every byte kept: **429 bytes**, against 180 KB inside tmux.
It is not the same protocol.

    ESC[?s ESC[*x ESC[4l …                          the usual mode setting
    ESC_G a=q,f=24,s=1,v=1,S=3,i=1        ;MTIz            can you take bytes?
    ESC_G a=q,f=24,t=t,s=1,v=1,S=87,i=2   ;<a temp path>   …a temporary file?
    ESC_G a=q,f=24,t=s,s=1,v=1,S=18,i=3   ;<a shm name>    …shared memory?
    ESC[c                                                  and are you there?

**Outside tmux `icat` asks the terminal what it can do, and waits for an
answer.** Inside tmux it cannot get one, so it never asks and falls back to
sending the whole PNG as base64. Answering those three the way this app's
`decode` does — OK, OK, `EBADF:shared memory transfer is not supported` — and
`icat` then sends its picture as one line:

    CR  ESC[53C  ESC_G a=T,q=2,f=100,t=f,s=732,v=988,X=2 ;<the file's path>  ESC\  CRLF

Against what every capture in this item and in 0397 has, which was tmux's:

    ESC_G a=T,q=2,f=100,m=1,U=1,s=732,v=988,X=2,c=46,r=26,i=2071036375 ;<180 KB>

Six differences, and five of them matter:

- **`t=f`** — the picture is a *path*, not 180 KB of base64. That is the whole
  429 bytes against 180 KB.
- **no `U=1`** — it is **not a virtual placement**. It is placed at the cursor,
  as a real entry in `graphics.placements`.
- **no placeholder cells at all.** No U+10EEEE, no diacritics, no rows written
  by `icat`. So the entire mechanism 0397 and this item measured — 22,448
  placeholder cells, `runs`, `withoutImage=0`, the offline replay — is about a
  path a plain pane never takes.
- **no `c=` and no `r=`.** `icat` says nothing about how many cells to use; the
  terminal works it out from the pixels. So "the `c=`/`r=` of every run is the
  first number to read" has no number to read here.
- **no `i=` and no `I=`**, so the terminal assigns the id.
- `m=1` absent: one chunk, because a path is short.

The `ESC[53C` is `icat`'s centring, `(153 − 46) / 2 = 53` — the same arithmetic
0397 closed column 62 with, arrived at by `icat` itself rather than by tmux
repainting spaces.

`Scripts/icat-notmux.py` in the item's folder is the harness: it runs a command
under a pty of a chosen size with `TMUX` unset and answers the graphics queries
as this app does, so what `icat` sends outside tmux can be read without a
window.

## What it turned out to be

**The cursor advance after a placement clamped instead of scrolling.**

A plain pane's `icat` places the picture at the cursor and expects the terminal
to make room for it — it is told nothing about how tall the pane is, and sends
no `r`. The terminal answers by moving the cursor down the height of the
picture, and `TerminalEmulator` did that with `moveCursor`, which clamps at
`screen.rows - 1`. So when fewer rows were left than the picture needed:

- nothing scrolled, and
- the placement kept the rows it had been given — absolute rows running past
  the bottom of the screen, which are never drawn.

Then the shell drew its prompt, and zsh writes `ESC[J` before every one of
them. `erasePictures` takes the pictures standing on erased rows, and a
placement stretching seventeen rows below the last visible one **overlaps
everything erased from the prompt downwards**. So the picture was placed, drawn
for one frame, and then erased by the prompt — while the gap stayed, because
the gap is the cursor having moved.

That is the original 0397 report word for word: *"the second shows the picture
and loses it while still reserving the space"*. And it is invisible inside
tmux twice over: `icat` uses placeholder cells there, which are re-derived from
the grid and cannot go stale, and tmux swallows the `ESC[J` — 0397 measured
exactly that and drew the opposite conclusion from it.

It also explains "it now works once". A first `icat` in a fresh pane has the
whole screen below the cursor, so nothing clamps and the picture draws. The
user's recipe fills the screen *first* precisely to take that room away, which
is why it reproduces every time and why nothing that did not fill the screen
first ever did.

Now the advance is a line feed per row. Feeding makes the room the picture was
promised: the retired lines go into the scrollback, every absolute row stays
where it was — which is what makes the whole scheme work — and the picture
lands wholly on the screen with the prompt below it.

## What this was waiting for

**It is not waiting any more**; the recipe above is what arrived. Kept because
it says what to capture, and because the first item asked for the wrong two
things: a `c=`/`r=` that a plain pane never sends, and a placeholder replay of
a path that has no placeholders.

One reproduction on the machine where it happens, with two things captured
while it is on screen. Neither needs a rebuild — the app in `/Applications`
does not have them yet, but any build from this branch does:

1.  Launch with `ABYDOS_TERM_LOG=/tmp/pane.log` in the environment and
    `--report-geometry`, run `kitty icat` four times in the pane, and keep
    both the log and the `GEOM` lines. The one to read is
    `winsize=<rows>x<cols> pixels=<h>x<w> ptyCell=<w>x<h>` — `ptyCell=0x0`
    would be this app telling the pane it cannot show pictures at all, and a
    `winsize` that disagrees with `rows`/`columns` on the same line is a
    second tmux client sizing the pane out from under the window.
2.  A photograph of the same four runs, so the log and the screen can be put
    beside each other.

Everything else 0397 and this item could ask has been asked. Without a
capture from a state where it fails there is nothing left here to measure:
what is measurable on this machine all says it works.

## What is still not shown

**The symptom did not happen here.** Eight sessions, four runs each, at three
pane heights, with GPU rendering on and off, fast and slow: four runs drew four
pictures every time, and the offline replay of every capture resolves every
placeholder row to a placement with an image behind it. Nothing in any capture
distinguishes run one from run two except that run one does not scroll.

So the fix below is the one real defect found on the way rather than a
demonstrated cure, and it is said that way on purpose. If it comes back, the
two things to capture are now one command each:

- `--report-geometry` prints `winsize=<rows>x<cols> pixels=<h>x<w>
  ptyCell=<w>x<h>` — read back off the device, so it is what the program sees.
  `ptyCell=0x0` is the terminal saying it cannot show pictures at all, and
  `winsize` disagreeing with `rows`/`columns` on the same line is a second
  client sizing the pane.
- `ICAT_LOG=<a term log> ICAT_ROWS=.. ICAT_COLUMNS=.. swift test --filter
  IcatCaptureReplay` replays a capture through the emulator and prints, after
  each run, how many placeholder runs resolved and how many resolved to a
  placement with no image behind it.

## What was fixed

A scale of zero is not an absent scale. `updateCellPixelSize` chose one with
`??`, which steps past an answer that is *missing* — and
`NSWindow.backingScaleFactor` is not missing when it cannot be given, it is
**zero**, which is what a window not on a screen reports while a display is
being woken, unplugged or moved between. Zero fell through the whole chain and
made a cell 0×0 pixels; since 0397 that answer is written to the pty and
signalled at once, so the program acts on it. A cell of no pixels is exactly
how a terminal says it cannot show pictures at all — `icat` then prints
nothing and reserves nothing, which is "no picture and no gap" — and it stays
that way for the rest of the session, because nothing measures a cell again
until the font or the display changes.

Now a scale is used only if it is positive, and when none is, the size the
program already has is left alone rather than replaced by a guess.

## Steps

- [ ] Reproduce it — four runs in one pane, in the app, on the current build
      — **not done**: eight sessions, four runs each, and it drew every time.
      What was tried is under "What was ruled out".
- [x] `ABYDOS_TERM_LOG` and `tmux pipe-pane` across all four, and the `c=`/`r=`
      of each written down here
- [x] Say what differs between run one and run two, in bytes
- [x] Account for the two prompts on consecutive lines after run one
- [ ] Fix it, and watch four runs in a row draw four pictures — **not done**,
      because there is nothing here to watch stop happening. One real defect
      on the path was fixed and is under "What was fixed"; four runs draw four
      pictures before and after it.
- [x] Ask a running app what the program was told the pane is
- [x] Replay a capture through the emulator from the suite, rather than by
      writing the harness again
- [ ] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` says what the project now does

The user then said the pane is not tmux, and these are the steps that made:

- [x] Capture what `icat` writes with **no** tmux, and say how it differs in
      bytes from every capture taken so far
- [x] A test that fails: a picture placed where there is not room for it keeps
      rows below the bottom of the screen
- [x] A test that fails: the prompt after such a picture erases it
- [x] Make the room instead of clamping the cursor
- [ ] Watch the user's own recipe — fill the screen, then four `icat` in a row
      in a plain pane — draw four pictures, with GPU rendering off and on
- [ ] Say which of 0397's rulings were taken inside tmux, which survive outside
      it, and which were never re-checked
