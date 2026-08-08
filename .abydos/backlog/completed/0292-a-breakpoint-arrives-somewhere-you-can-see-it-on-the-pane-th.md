# A breakpoint arrives somewhere you can see it, on the pane that has something to say

`2297203e7` · 2026-08-05

Two ways the debugger had nothing to show at the moment it had everything to
show.

The terminal can have the whole window — ⌘⏎ is one keystroke — and a program
stopping behind it stops invisibly: the editor is hidden, not merely small. So
stopping gives the window back and keeps at most half of it for the panel.
Half rather than a fixed height, because the stack, the variables and the
console need room too, and taking the panel down to a strip to reveal one line
is the opposite mistake.

And the pane showed variables from the start, which is the wrong half of the
session: a program that is running has a log worth reading and no variables to
speak of, and the instant it stops that reverses. The two do not fit side by
side at any panel height somebody would actually choose, so the pane follows
the session instead of asking — the console until it stops, the variables from
then on.

Verified against a real session: with the terminal maximised, a breakpoint in
the go-service example brings the editor back at a third of the window with
the variables showing `stage` and `started`.
