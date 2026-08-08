# tmux's status bar goes away without being asked twice

`2055fdd70` · 2026-08-04

Turning the setting off and on again was the workaround, and it was also the
only other thing that ever re-sent the command — which is the whole bug.

`set-option -t <session> status off` fails quietly when the session is not
there yet, and at startup it usually is not: the poll that sends it begins
before tmux has finished being created. The exit code went nowhere, the
panel recorded "told this one" regardless, and the guard that keeps it from
running tmux twice a second then held for the rest of the session.

So the command is now checked, and remembered only when tmux actually heard
it. Anything that went nowhere is simply sent again by the next poll.

And the bar is asked about afresh every twenty seconds or so, because a
session option does not outlive its server: `tmux kill-server` and whatever
restarts it comes back with the bar on, and nothing about that reaches this
app. Against a poll that already runs tmux every tick, one more question in
forty is cheap enough to be worth never being wrong about.

Verified against a real session: the bar goes off two seconds into a cold
start, and when it is forced back on from outside it is off again thirteen
seconds later.
