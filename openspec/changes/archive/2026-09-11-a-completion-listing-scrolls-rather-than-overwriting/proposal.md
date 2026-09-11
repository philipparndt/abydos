## Why

A user's report, relayed on 2026-09-09: *"cd tab tab zeigt die Liste der
Verzeichnisinhalte. Überschreibt vorherigen Output der dargestellt wird statt
zu scrollen."* Typing `cd`, then tab twice, shows the directory listing — and it
overwrites the output already on the screen instead of scrolling it up.

The maintainer could not place it from the sentence, so this proposal starts by
saying what it most likely describes, and its first task is to reproduce it.
The shell's completion listing is drawn *below* the prompt. When the prompt is
near the bottom of the screen and the listing needs more rows than are left,
the shell makes room: it moves the cursor to the bottom and emits line feeds
until there are enough, which scrolls everything above into the scrollback,
then draws the listing and moves back up to the prompt. What the report
describes is the making-room step not scrolling — the listing landing on top of
the rows that were there — which means either the emulator did not scroll on a
line feed at the last row, or the cursor was not where the shell believed it
was when it started. Three places that could be:

1. `TerminalEmulator.lineFeed` scrolls only when `cursorRow == scrollBottom`; a
   scroll region left narrower than the screen by a full-screen program that
   exited without resetting it would put the bottom above the last row.
2. The shell's idea of the screen height. If the rows reported to the
   pseudo-terminal are not the rows drawn — a pane resized, a hidden tmux
   status line — the shell's arithmetic for how many line feeds to emit is off
   by that much, and it draws over rows it thinks it has scrolled away.
3. tmux itself, which most people here run inside every pane: tmux redraws a
   pane from its own model, and a listing that scrolls correctly in tmux's
   model but is painted over stale rows is a redraw the emulator missed.

Which one it is decides who fixes it, and reading cannot tell them apart.

There is no originating `.abydos/backlog` item: this comes from a relayed user
report, 2026-09-09.

## What Changes

- **Reproduce first.** A driven run fills a pane to the last row, types `cd`
  and two tabs into a zsh with the default completion, and prints the rows
  before and after — under both engines, with and without tmux, with the tmux
  status line hidden and shown. The design records which of the three it is,
  or that it does not reproduce and what was ruled out.
- **Fix what is named.** Nothing else; a scroll-region reset added on a guess
  would appear to work.

## Capabilities

### Modified Capabilities

- `terminal`: a line feed on the last row of the scroll region scrolls, and
  the rows a shell is told about are the rows it is drawn in.

## Impact

- **AbydosKit**: `TerminalEmulator` if it is the first or second; nothing if it
  is tmux's redraw, in which case the finding is about `GhosttyTerminalEngine`
  or the pane's size reporting instead.
- **Left open**: the user's shell and whether they run tmux. Asked for when the
  reproduction does not reproduce.
