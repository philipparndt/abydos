# Nothing unfinishes a turn

`b4bc45abf` · 2026-08-04

"docscanner finished" arrived and the tab kept spinning, then went
amber. Both from the same cause: a subagent handing its work back after
the turn that sent it off had already ended set the badge to "working"
again, and with the window no longer saying "done" the idle nudge that
followed was free to turn it to "needs you".

A subagent finishing means the session is still working only while it
is. On a window that says the turn is over it now changes nothing and
says nothing — the same rule the nudge already followed, and the two
are now one line.

The whole sequence is a test: prompt, subagent, stop, straggling
subagent, nudge, next prompt.
