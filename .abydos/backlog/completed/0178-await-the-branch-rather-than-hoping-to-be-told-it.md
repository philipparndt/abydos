# Await the branch rather than hoping to be told it

`fe4addb4d` · 2026-08-02

The branch pill was being pushed a value it might not exist to receive: the
toolbar builds its items when it chooses, and in a repository small enough
git answers first. Caching the last answer papered over it. The read is a
task now — one per scope, kept — and whatever needs the branch awaits it,
whenever it comes into existence. A checkout goes through the same read, so
the panes, the tree's colours and the pill all follow from one place.

The subproject is written in the tree the way the project above it is, bold
and bright, with its folder in blue. It is a project here; the colour says
which of the two everything is pointed at. The green dot beside the name is
gone — a mark there reads as a status, and this is not one.
