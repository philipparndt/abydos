# Refresh the project tree when the window comes forward

`3f6687dbb` · 2026-07-31

Coming back to the window already reloaded externally changed files in the
editor, but left the tree showing whatever it last read. An agent adding
files while the app was in the background stayed invisible until something
else happened to fire.

The watcher was also ignoring the event flags. A burst too large for
FSEvents to describe file by file — a checkout, a build, an install —
arrives as "this directory changed somehow, look again", and reporting its
parent, as the code did for ordinary events, missed everything underneath
it. Watching the root as well means renaming the project directory no
longer leaves the tree pointing at a path that is gone.
