# Make tmux's strip look and behave like tmux

`2d906261d` · 2026-08-03

The bar is green from end to end now, not green tabs on the app's own
background — the strip across the foot of the screen is the thing
everybody recognises — with the active window cut out of it in the
terminal's own dark, dividers and the + in the ink tmux writes with, and
no step between the cut-out and the terminal directly above it.

Fixes from using it:

- The badges no longer blink and the tabs no longer jump. Marking a tab
  active optimistically rebuilt each window from four fields and dropped
  its Claude status, so every switch blanked the badges until the next
  poll — and since a badge set the tab's width, the tabs shuffled. Room
  for the badge is now always reserved on tmux's strip, so a session
  starting or finishing work moves nothing.
- The top strip is no longer wired to tmux. Its items had been split out
  but the arithmetic behind its clicks had not, so selecting an ordinary
  tab drove tmux's windows.
- tmux's strip belongs to the tab tmux is in: it is gone while anything
  else is showing, and that tab is marked with a green icon so it is
  clear which one owns it. The terminal attached to tmux is now tracked
  rather than assumed to be the first in the list, which stopped being
  true when the tmux tab became closable.
- A working badge is not believed after half a minute of silence. Claude
  prints constantly while it works, so a quiet "working" is a leftover:
  a session that was mid-turn when the app closed, or one that was
  already running before the hooks were installed.
- Detaching is noticed. The session outlives the client, so the tabs and
  the phantom row used to stay for a terminal that was back to being a
  plain shell.
