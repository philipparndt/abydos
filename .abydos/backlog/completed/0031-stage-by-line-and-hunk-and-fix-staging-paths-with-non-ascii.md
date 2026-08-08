# Stage by line and hunk, and fix staging paths with non-ASCII names

`8b31442aa` · 2026-07-31

File staging failed outright on any path containing a non-ASCII
character: git escapes those in its default porcelain output —
"kühlschrank" arrives as "k\303\274hlschrank" inside quotes — and the
escaped form matches no file. Both status readers now ask for `-z`,
which writes paths out literally. The quoted-path decoder is fixed as
well, for the newline-separated fixtures the tests use: escapes are one
octal triple per *byte*, so decoding them individually yields two
Latin-1 characters rather than the one they encode. The bytes are
collected and decoded as UTF-8 at the end instead. The navigator's own
status reader had the same fault, so non-ASCII names were coloured
wrongly there too.

Line and hunk staging is built on a new patch model. Staging part of a
diff means handing git a patch containing only what was chosen, and that
patch has to be internally consistent or `git apply` rejects it, so hunk
counts and post-image starts are recomputed rather than copied.

The subtle half is what happens to lines that were *not* chosen, which
depends on which side the patch must match. Applying forward, an
unselected addition never happened and is dropped, while an unselected
deletion means the line stays and becomes context. In reverse — which is
what unstaging is — it inverts: the addition is already in the index and
has to be carried as context, and the deletion is not there at all and
goes. Getting either backwards produces a patch git refuses, or worse,
one that applies and stages something nobody chose. Both directions are
covered by tests against real repositories.

In the diff, clicking a hunk header takes the hunk, clicking a line
takes the line, and shift- and command-click extend as usual. Return or
the context menu applies. Discarding lines asks first, since it is the
one operation here that destroys work.

Also: the sidebar strip buttons are tabs now. They were wired to "toggle
the sidebar", so clicking Project while the staging view was up
collapsed the sidebar instead of switching to the tree — and getting
back meant pressing the other button twice. Picking a tool now shows it;
clicking the one already showing closes the sidebar.
