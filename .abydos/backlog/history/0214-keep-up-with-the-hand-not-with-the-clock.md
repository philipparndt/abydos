# Keep up with the hand, not with the clock

`71bcb02f7` · 2026-08-03

Switching a tab moved tmux at once and the strip a moment later, which reads
as an interface trailing its own clicks.

Three changes. A tab clicked marks itself active before tmux has answered —
it is the one thing here that can be known without asking, since we are the
ones asking for the switch. Every command that changes the session asks again
as soon as it returns rather than waiting for the next tick. And output from
the terminal is taken as a cue that tmux may have moved on its own: a window
switched by its own keys redraws the screen, so the strip looks again a
tenth of a second later — coalesced, since a build's output is thousands of
chunks and one question covers all of them.

The half-second poll stays as the backstop for what none of those catch.
