# Push from the commit view, and notice what happens outside it

`3ea981a2a` · 2026-08-01

The push button says what it would send — "Publish Branch" for a branch
with no upstream, "Push 3" for one that is ahead — and is disabled when
there is nothing to send. git is told not to prompt: it would ask on a
terminal that is not there and hang with nothing on screen to explain
why, where refusing turns that into a message that can be read.

A second watcher follows .git, so committing, pushing or switching
branches in a terminal updates the history, the branch list and the
changes view. Loose objects are ignored: a fetch writes thousands and
none of them says where a branch points.
