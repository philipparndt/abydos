# 393. tmux's own prompts have nowhere to appear when its bar is off

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

Its number is where it sits in the queue, not what it is worth doing next —
by the ordering the README describes, a bug that stops somebody working
belongs above the three tasks before it.
