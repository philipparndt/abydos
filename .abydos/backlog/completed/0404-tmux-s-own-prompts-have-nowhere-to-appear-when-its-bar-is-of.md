# 404. tmux's own prompts have nowhere to appear when its bar is off

Pressing prefix-`,` to rename a window, or prefix-`:` to run a command, inside
a pane where something is busy — Claude Code working — leaves no prompt worth
typing into. Sometimes nothing appears at all; sometimes a fragment does, in
the wrong place, and is gone by the next repaint. Whatever was typed then goes
somewhere invisible, which is worse than nothing happening.

**This app turns the bar off, and that is where those prompts live.** Two
places do it, and both are meant to: `TmuxConfig` writes `set -g status off`
into `~/.tmux.conf` and applies it to the running server, and
`TmuxMirror.setStatusBar` sets `status off` per session. The reason is good —
the panel already draws the same window list as tabs, and two rows of it is one
too many — but tmux draws its command prompt, its messages and its menus on the
status line, so turning that off takes the prompt with it.

**What tmux does with no status line is borrow the pane's last row**, which is
ordinarily fine: a shell waiting at a prompt is not writing anything, so the
row stays as tmux painted it. It is not fine against a program that repaints —
Claude Code writes over that row constantly, and the prompt is gone within a
frame of appearing. The screenshot is one caught mid-way: a yellow strip partly
drawn over the pane's own output, above this app's tab strip.

So the reported "sometimes" is exactly "whenever something in the pane is
busy", and the row being borrowed is a row the pane owns and will overwrite.
Reproducing it needs a busy pane, not a quiet one: `yes | head -c 1000000` in
the pane, then prefix-`,`.

Worth confirming on a socket of its own, with a client attached, before
choosing between the three answers below — `tmux -L probe display-message -p
'#{client_prompt}'` says whether tmux thinks a prompt is up while nothing can
be seen. (`command-prompt` needs a real attached client: with none it answers
"no current client", and an attach under `script -q /dev/null` blocks the shell
it was started from, which is what made the first attempt at this useless.)

Three ways out, and they are not exclusive:

- **Turn the bar on for as long as a prompt is up.** tmux knows when one is up
  (`#{client_prompt}`), but nothing here is watching, and the pane would have
  to be resized a row and back — the resize is the part that has already been
  found not to work (see `TmuxConfig`'s note on reporting a taller pane).
- **Answer the prompt ourselves.** Renaming is already done properly in the
  app: a double-click on a tab renames in place, and `TmuxMirror.rename` is
  what carries it out. So prefix-`,` could be caught before tmux sees it and
  turned into that field, which is the better version of it anyway. The same
  cannot be said for prefix-`:`, which can run anything.
- **Give the command prompt a row of our own.** The tab strip is ours and is
  already the bottom of the window; a one-line field above it, driven by
  `command-prompt` output, would put the prompt where somebody is looking.

Whatever is chosen, the case to keep in mind is the one reported: the pane is
*busy*. A fix that works against a quiet shell and not against a program
writing every frame has not fixed this.

---

## What it turned out to be

None of the three. The prompt was being drawn, on time, and one row too high —
by this app's terminal emulator, from an address tmux gave it.

### tmux parks its cursor below the screen, and then draws relative to the park

With the bar off and a prompt up, tmux puts the terminal cursor one row *below*
the last row of the screen: `CSI 31 d` on a 30-row client, `CSI 25 d` on a
24-row one, so it is `rows + 1` and not a constant. It then writes the prompt
by moving up from that park with `CSI A`.

There is no row 31 on a 30-row screen, so the park is clamped to the last row —
this emulator clamps it, and so does every other. Move up one from the clamp and
you are on row 29: one above where the prompt belongs, in the middle of the
pane, on top of output the pane owns. That is the screenshot exactly — a yellow
strip partly over the pane's own text — and it is why it does not last: the row
it landed on is a row the pane repaints.

`moveCursor` now remembers that it was asked for the row one below the screen,
and `CSI A`/`B`/`E`/`F` count from what was asked for rather than from the
clamp. One row and no further: a program asking for row 999 is guessing at the
size of the screen rather than parking on the edge of it. The flag lasts until
something puts the cursor somewhere real — a character drawn, a line fed, a
move that lands on the screen — which is the same life `pendingWrap` has, one
edge over. It is called `isParkedBelowScreen` and the note above it says all of
this.

### The premise in the report above is wrong, and worth correcting

"What tmux does with no status line is borrow the pane's last row … It is not
fine against a program that repaints" — it is fine. **tmux holds that row.**
Between the prompt appearing and it being dismissed, tmux sends nothing at all
for the pane: in a capture of a pane printing twenty lines a second, three
seconds of it produced zero bytes, and a capture of a pane repainting all
thirty rows twenty times a second the same. The last line does not need
protecting from the panel; tmux is already protecting it. The whole of the
fault was that the prompt was not being put on it.

So there was nothing to catch before tmux saw it, no bar to turn on and off, and
no row of our own to draw. Those three remain available and none of them was
built.

### What was measured, on a socket of its own

Every tmux here ran as `tmux -S <private socket> -f <own config>` with a client
attached inside a pty, and each server was killed and its socket removed. Never
the default socket: a `tmux` without `-S` is whatever server the person running
it is sitting in, and one with `-f` and without `-S` takes their settings with
it.

- 30 rows, status off: park at `CSI 31 d`. 24 rows, status off: `CSI 25 d`.
- 30 rows, **status on**: `window_height=29`, no park at all, the prompt drawn
  from a `\r\n` onto the bar below the pane. The park is what the bar being off
  does.
- `#{client_prompt}` was empty in every `display-message` answer, prompt open or
  not, so it is not the handle the report above hoped it was — at least not
  asked from another client.
- tmux waits about three seconds after the prompt opens and then redraws the
  whole client, prompt included, addressing every row absolutely. **Why three
  seconds is not explained here.** It is the same delay after each keystroke
  into the prompt, and it is what made the prompt seem to arrive late rather
  than wrong.

### Two captures, and a live test that was written and thrown away

`Tests/AbydosKitTests/Fixtures/tmux-prompt-repaint.bin` is 24×60 with the pane
repainting every row by absolute address ten times a second — the reported case,
and the one that carries the fault. `tmux-prompt.bin` is 30×100 with the pane
scrolling, which is what anybody reaches for first and which *never showed the
fault*: against a scrolling pane the cursor is already on the last row and tmux
draws the prompt where it stands. Both are replayed by `TmuxPromptTests`, and
the repainting one fails on the first prompt draw without the fix.

A live test driving a real tmux through `PseudoTerminal` was written and then
deleted, because it passed with the bug present. tmux has two ways of drawing
the prompt — from the park, and from an absolute `CSI 24;1H` — and which one it
picks depends on whether the pane's frame was flushed before the keypress was
handled. A Python-driven client hit the park path every time; the same tmux,
same config, same pane, same rows, driven from Swift, hit the absolute path
every time, through six variations of frame rate, how the pane batched its
writes, how fast the client read, and a resize.
**I could not find what decides it**, so a live test would have been a guard
that fails to fail. One thing that variation did turn up and that is worth
keeping: TERM decides how tmux moves the cursor, and a suite run from *inside*
tmux inherits `tmux-256color`, under which tmux draws its prompt with no cursor
motion at all.

### Not covered

Only the emulator was changed, and only for the cursor. If the prompt is still
hard to use it will be for a reason this did not touch — the three-second
redraw, or the fact that a prompt on the pane's last row is a prompt where
nobody is looking, which is what the third way out above was for.

---

Its number is where it sits in the queue, not what it is worth doing next —
by the ordering the README describes, a bug that stops somebody working
belongs above the three tasks before it.

---

Previously numbered 393.
