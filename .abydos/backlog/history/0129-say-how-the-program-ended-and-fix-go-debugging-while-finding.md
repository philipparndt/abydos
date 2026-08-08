# Say how the program ended, and fix Go debugging while finding out

`0205dc0a0` · 2026-08-01

"Finished" is the same word for a clean run and a crash, which is the one
thing worth knowing without reading the log. The toolbar now says the exit
code, and says it in red when it is not zero.

Where it comes from depends on the debugger. LLDB reports it properly in the
`exited` event. Delve never sends that event at all — it says it in a
sentence on the console, which is where VS Code reads it from too, so that
is parsed as a fallback. An adapter that reports it properly is believed
over anything found in prose. Where neither happens it still says
"Finished", because inventing a zero would be worse than saying nothing.

The test for this found that Go debugging had been broken since adapters
were generalised for LLDB: a package is named relatively — "." or
"cmd/server" — and the generic launch path stopped resolving that against
the project. It resolved against the *app's* working directory instead, so
delve was pointed at wherever ideai itself had been started from, where the
build failed with nothing said about it. Sessions simply sat at "Starting…"
for ever. Resolved before anything else touches the path now, so every
caller gets it right.

Also: the history's scope switch is two segments with the active one lit,
rather than one button whose label named the other state — "Only main.go"
and "Whole Repository" both read as descriptions of what is showing, so a
single button could not say which it was.
