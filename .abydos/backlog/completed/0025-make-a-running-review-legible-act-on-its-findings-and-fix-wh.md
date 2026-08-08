# Make a running review legible, act on its findings, and fix what it found

`960a353af` · 2026-07-31

The review did not start until the chat was opened. The terminal waits
for a real size before launching the agent, so it does not hand a
full-screen program a grid a few rows tall — but the pane swapped the
findings list and the terminal in and out of the view hierarchy, so the
terminal had no size until someone went looking for it. Both views are
now installed once and switched by visibility; a hidden view is still
laid out.

Even once it runs, there was no way to tell a working review from a hung
one without switching to the chat. The header now counts elapsed time,
and a tail of the agent's own output sits under the findings with a
spinner. Lines made only of frame are skipped: a full-screen TUI pins
its input box to the bottom, so the last non-blank lines are its
borders, which say nothing about whether anything is happening.

Findings can now be selected in bulk and copied as `path:line` text, or
handed back to the live session — "Chat About This" or "Explain
Visually", the latter asking for a diagram of the failing path. Sending
them into the same session reuses the context it built while reviewing,
which is the reason that session is kept alive.

The header also drew its status without reserving room for the buttons,
so a long one ran underneath them. The buttons are laid out first now
and the status truncates.

The first review this produced found real bugs in the terminal work of
the previous commit, all fixed here:

- ST-terminated OSC left the backslash of `ESC \` on screen, because
  finishing the string returned straight to ground rather than letting
  the escape handler consume it.
- columnRange clamped its lower bound but not its upper, so a selection
  made before the grid narrowed built a reversed range and trapped.
- The parameter parser and the private-sequence guard recognised
  different introducer sets; they now share one.
- The guard covered only `m`, so `CSI = c` still answered as a primary
  device-attributes query — a reply to a question nobody asked, which
  the shell then echoes.
- Double- and triple-click used a rounded cell boundary as a character
  index, so clicking the right half of a cell selected the next word.
- The terminal context menu set isEnabled on items in a menu that
  auto-enables, which discards it.
- Powerline separators were drawn for hidden runs.
- Selections held absolute rows that nothing renumbered when scrollback
  was trimmed, so they drifted; the screen now reports how many lines it
  has discarded and the view follows.
