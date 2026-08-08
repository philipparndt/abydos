# 398. Blank rows appear while the Return key repeats

Holding Return produces a full-width blank row between prompt lines,
irregularly. In tmux and in a plain tab.

`Tests/AbydosKitTests/Fixtures/return-burst.bin` is 9075 bytes captured from a
live login shell — 45 presses, 33ms apart. Replay is deterministic.
`Tests/AbydosKitTests/ReturnBurstTests.swift` replays it with no UI at all, and
**the blank rows come back**: 30 rows at 100 columns, prompts at 2, 3, 6, 9 …
and blanks between them.

**Asked and answered: Ghostty does not do it**, with the same shell and the
same prompt. Which pointed at this terminal — but the replay says otherwise,
and says it with a second implementation as the witness.

## What the replay showed

The blank rows are in the bytes. Every press is

    \x1b[?2004l \r \r\n            accept the line
    % + 99 spaces \r ' ' \r        zsh's PROMPT_SP filler, exactly one row
    (\r\n × k) \r                  k extra line feeds, k = 0…3
    \x1b[0m\x1b[27m\x1b[24m \x1b[J erase from here down
    ' ~ ' <powerline> \x1b[K       the prompt

The filler is `%` plus `columns - 1` spaces, which fills the row exactly; the
`\r`, space, `\r` walks back and overwrites the `%` with a space, so the row is
now blank, and `ESC[J` is supposed to land on that same row and erase it. When
`k > 0` the erase happens `k` rows lower instead, so the blanked filler row is
left standing. That is the blank row, one per extra line feed. In the capture
`k` is 3 for 26 of the 45 presses, 2 for ten, 1 for six, 0 for four.

Replaying the same file into **tmux** at 30×100 and comparing
`capture-pane -p` against our grid gives **an identical 30 rows**, blanks and
all. So the emulator is not adding them and not absorbing one either.

## What it is

The extra line feeds are the shell's, and no terminal is involved in making
them. Driving a real `zsh -l` under a **bare pty** from a twenty-line Python
script — `pty.fork`, `TIOCSWINSZ` to 30×100, write `\r` every 33ms, read the
master — reproduces the same tails, the same shapes, the same irregularity.

Which shell configuration it is, narrowed by swapping only `ZDOTDIR`, 45
presses at 30ms each time:

    zsh -f                     45 accept-lines, 45 line feeds   one row per press
    eval "$(starship init zsh)" 45 accept-lines, ~300 line feeds  six or seven

So it is starship, or starship losing a race. It is rate-dependent, which is
why it is irregular: at 300ms between presses the same shell emits four extra
line feeds in the whole run, at 30ms it emits three hundred. Starship runs a
subprocess per prompt, and 30ms is roughly the macOS key-repeat interval.

## Ruled out

Everything on this side of the pty, most of it now nailed down by experiment
rather than by reading:

- **The emulator.** Identical grid to tmux over the same bytes, and
  `advancesOneRowPerLineFeed` pins the invariant that matters: the document
  grows by exactly the number of line feeds in the capture and not one more.
  An early wrap off that full-width filler would show up here first.
- **Anything we send unasked.** `answersNothingTheShellDidNotAsk` asserts the
  capture draws no reply at all; every `onResponse` in the emulator sits inside
  a query handler, and the capture contains no queries. Device attributes, mode
  reports, focus 1004 and bracketed paste are all clear.
- **The key path.** `keyDown` sends one `\r` per press straight to the pty —
  no repeat filtering, no doubling through `interpretKeyEvents`.
- **The termios we hand the shell.** `forkpty(&master, nil, nil, &size)` passes
  no termios at all, so the child gets the kernel default, the same as any
  other terminal.
- **`TERM`.** We set `xterm-256color`. Running the burst with `xterm-ghostty`
  instead changes nothing.
- **The tty echo.** Clearing `ECHO` on the slave before `exec` changes nothing
  either, so the extra feeds are zsh's own writes, not the line discipline
  echoing keys typed between prompts.
- **A slow drain widening some window.** A reader that sits on its hands 50ms
  before every read makes it *better*, not worse.
- Previously, and by reading: a split-sequence parser bug, a data race, an
  unclosed `pendingWrap` after a carriage return, a spurious resize from
  `recomputeGridSize`, and a scrollbar taking width.

## The one next step

The two halves no longer meet: the bytes carry the blank rows, no terminal is
needed to produce those bytes, and yet Ghostty is reported not to show them.
One of those is wrong, and one capture settles which.

Hold Return in Ghostty under `script -q /tmp/ghostty-burst.bin zsh -l`, with
the same starship prompt and the same 100 columns, and count the line feeds
between `\r \r` and `ESC[J`. If they are there, Ghostty shows blank rows too
and this belongs to starship — close it, and tell starship. If they are not,
the difference is what makes zsh *slower* under this terminal than under that
one, and the thing to measure is the wall time from the filler being written to
the next `ESC[J`, not anything about the grid.

---

Previously numbered 52, 386.
