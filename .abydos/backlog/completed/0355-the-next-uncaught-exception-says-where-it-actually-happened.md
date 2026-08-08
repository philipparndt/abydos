# The next uncaught exception says where it actually happened

`81afba989` · 2026-08-07

A crash report symbolicates a release build by nearest exported symbol, which
for a Swift binary is regularly a function with nothing to do with the crash:
a report of a nil in a text attribute pointed at a menu action fifty lines
away from any drawing, and following it wasted an hour.

The exception knows better — its stack is captured where it was raised — so an
uncaught one is written to a log that outlives the process, name, reason and
all. That does not fix the nil, and nothing here pretends to: what it does is
make the next occurrence identify itself rather than be guessed at.
