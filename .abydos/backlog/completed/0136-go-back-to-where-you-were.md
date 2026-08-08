# Go back to where you were

`8274f45d1` · 2026-08-01

One list with a cursor in it, the way a browser works: jumping somewhere
new from the middle drops the future that was there, and returning to a
line you are already on is not a step. ⌘[ and ⌘], as IDEA has them on
this platform. Where you were is recorded at the caret rather than at
whatever line the file opened on, so back returns to what you were
reading.

Language servers are also spoken to in real paths now. A server resolves
a module by realpath, so a workspace given as /tmp/x did not contain the
module it had just found at /private/tmp/x — gopls said so and then
answered nothing about any symbol in it.
