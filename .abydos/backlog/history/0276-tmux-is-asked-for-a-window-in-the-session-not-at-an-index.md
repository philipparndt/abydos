# tmux is asked for a window in the session, not at an index

`fcc918db0` · 2026-08-04

`new-window -t ideai` is not "a window in the session ideai". Without the
colon tmux reads the argument as a *target window* — the session's current
window — and then asks for the new one at that index. On a session sitting
on window 0 the answer is "create window failed: index 0 in use", every
time, which is why this failed on a real session and passed on every test
one I built: mine happened to be sitting somewhere with a free index above.

`=<session>:` is what was meant. The colon means the session itself, next
free index; the `=` means that session rather than anything it is a prefix
of — this app has `ideai` and `ideai-examples` open at once.

The same `=` goes on the other commands that name a session, for the same
reason.

And the button no longer falls back to opening a terminal. That fallback is
how a press on tmux's window list kept putting tabs in the panel's own
strip: two separate things, and a button on one quietly adding to the other.
Whatever tmux refuses, it says so now — attaching lives on the session tag,
which is where somebody goes when the session is what is missing.

Found by asking the app to write down what it decided rather than reasoning
about it again: the log said `newWindow=false`, and tmux, asked by hand,
said why.
