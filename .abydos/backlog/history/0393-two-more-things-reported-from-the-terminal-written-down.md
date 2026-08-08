# Two more things reported from the terminal, written down

`31e5d39fd` · 2026-08-08

tmux draws its command prompt and its messages on the status line, and this
app turns that line off because the panel already shows the same window list
as tabs. With no status line tmux borrows the pane's last row, which is fine
against a shell that is waiting and useless against a program that repaints
— so renaming a window or running a tmux command while Claude Code is
working leaves nothing to type into, and what was typed goes somewhere
invisible.

And ligatures in a pane depend on which pane holds the cursor, in both
directions: one report has the operators joining only while the pane is
inactive, a later one only while it is focused. Each state joins something
the other does not, which rules out the setting and the font and points at
what the shaper is being handed — a run ends where the cell attributes
change, and an operator whose first character carries a different attribute
cannot join by construction.

Neither is fixed. Both carry what has been ruled out and what to measure
first, which is the point of the open list.
