# A graph in the history, and a strip that still holds everything else

`36a0e50a9` · 2026-08-03

The history draws its shape. Every line of descent gets a lane, kept for as
long as it lives, and the lanes are laid out from the commits and their
parents alone — no colours, no geometry, no view — so the shapes that are
miserable to build in a repository can be tested as fixtures. A merge is a
ring rather than a dot, since what matters there is the two lines meeting;
the lines bend rather than corner, so the eye follows them round.

A merge can fold the branch it brought in away, marked with a − beside its
ring and a + when it is folded. What gets hidden is what is reachable from
the second parent and not from the first — the commits somebody would call
"the branch that was merged" — and nothing that is also on the mainline goes
with it. A search or a path filter drops the lanes entirely: the commits
between the ones shown are missing, so what would be drawn is not the shape
of anything.

And the mirrored strip no longer takes the panel over. A run's output, a
debugger, a search, a second terminal — all of them keep tabs of their own
beside tmux's windows, which is what a build starting used to break. Their ✕
is back too; only a tmux window has none, because killing one can take a
build or an ssh session with it.
