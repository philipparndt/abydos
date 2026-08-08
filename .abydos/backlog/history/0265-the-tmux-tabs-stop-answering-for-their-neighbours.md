# The tmux tabs stop answering for their neighbours

`d121db57c` · 2026-08-04

Three faults with one cause: several places took "the terminal attached to
tmux" to mean "the first pane in the panel". That was the same thing for
as long as only the very first pane could be the attached one — and the
previous commit that let a terminal opened *after* something else be the
attached one turned the assumption into three visible bugs.

Clicking a tab activated the one to its right. The strip is built as the
tmux terminal first and everything else after it, while a click mapped the
position straight into the unfiltered list — correct only while that
terminal happened to be first in the list too.

The + made a plain console tab where a tmux window was wanted. The poll
asked tmux which session was on `sessions.first`'s tty; with a search pane
first there is no tty at all, so it concluded the client had detached and
emptied the window list. That took the tmux tabs off the strip, took the
green strip with them, and left the panel's own + as the only one on
screen — the button that makes a plain terminal.

And switching tabs flickered. The poll, output arriving and the click
itself each started their own pair of `tmux` processes, and the answers
came back in whatever order they finished: the click moved the highlight,
an answer from before the click moved it back, and one from after moved it
again. One question is in flight at a time now, with at most one queued
behind it, and an answer worked out before a local change is recognised
and dropped rather than published.

`--click-panel-tab <index>@<seconds>` prints what the strip is showing and
what a click on that position actually brought forward. The two being the
same thing is the point, and nothing else could see them disagree.
