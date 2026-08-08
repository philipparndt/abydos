# An integrated terminal can be opened again after the last one is closed

`b26799c26` · 2026-08-04

Close the tmux tab and there was no way back to one: every + gave another
plain shell, and no amount of pressing it produced a terminal attached to
the session the tabs still belonged to.

The panel decided whether to run `tmux new -A -s <session>` from whether it
held any panes at all. That is not the question. The question is whether one
is *attached*, and after closing the tmux tab the panel held an attached
terminal that no longer existed — so a leftover pane of any kind, a search,
a debugger, a shell opened for one command, was enough to make a plain shell
the only thing the + could ever produce again.

"Open Terminal Here" is excluded explicitly. Attaching puts you wherever
tmux left that shell, and the directory being asked for is the whole point
of asking.

Verified by building it both ways against the same script: with the old
rule the session had no client after pressing +, with this one it has its
client back and the same single window.

`--close-terminals <seconds>` closes every terminal tab the way the ✕ does,
and `--tab-add` now takes an optional time, since checking this needs the +
pressed after something else has happened rather than three seconds in.
