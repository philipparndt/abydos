# A launch that started nothing says what it was told, not what it guessed

`f956be4c8` · 2026-08-06

The watchdog named the one cause it knew — macOS holding a debuggee until
developer-tools authorization is answered — whatever had actually happened.
That is right when the adapter said nothing at all, and wrong the rest of the
time, expensively: a Go build failing with `cannot find main module` was
reported as a permissions problem, and the next hour went to
`DevToolsSecurity`, `tccutil` and the privacy settings rather than to a
missing `go.mod`. Delve had already printed the reason, in the console, above
the message that talked over it.

So the tail of what the adapter said is kept and shown, and the
authorisation note is left for the case it describes: nothing said, because
the debuggee was held before it could say anything. The tail rather than the
head — a build prints its command first and its complaint last.

Also: a terminal that is behind no longer draws every batch. Parsing yields
so the screen can be drawn between batches, which is right while output
arrives as it is produced and wrong when there is a backlog: each batch
paints a picture the program has already replaced, over a hundred a second.
A locked screen stops the drawing and not the program, so an animating
spinner arrives as minutes of frames at once and the screen flickers through
its own history. Twenty a second while behind, and once more on catching up.
