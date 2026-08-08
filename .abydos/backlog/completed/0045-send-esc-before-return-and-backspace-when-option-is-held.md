# Send ESC before Return and Backspace when Option is held

`fb4d115e6` · 2026-07-31

⌥Return sent a bare carriage return, which submits the line instead of
breaking it — so pressing it in Claude Code sent the half-written message
rather than starting a new line in it. The Option-as-Meta rule existed,
but the table of fixed key sequences returned before ever reaching it.

The rule now applies to the keys that stand for a character: Return,
Backspace, Tab, Escape and forward delete. ⌥Backspace was broken the same
way and now deletes a word.

Arrows and navigation keys are deliberately left out. Their modifier
belongs inside the CSI sequence, and prefixing one produces ESC ESC [ D,
which nothing parses — that would break word-wise movement rather than
enable it.

The table moved to IdeaiKit so it can be checked without a window or a
running shell.
