# Go to a symbol by name, and send nothing before the handshake

`235478570` · 2026-08-01

⇧⌘O lists what is declared in this file, ⌥⌘O searches the whole project.
Both come from the language server — `documentSymbol` and `workspace/symbol`
— so they know what a symbol is rather than what a regular expression thinks
one looks like. The nested document tree is flattened, since a "go to" wants
every declaration and not an outline, and each entry jumps to the name
itself rather than to the top of the declaration it belongs to.

Servers match loosely, so the sort has to put what was actually asked for
first: exact, then prefix, then merely containing, and shorter names before
longer. Without that a three-letter query answers with a five-hundred
character initialiser.

The bug this uncovered is the important part. Documents were being announced
before `initialize` had finished, and a server rejects everything that
arrives before that — quietly. The document was never registered, and every
later question about it came back "no language service for this file". That
was not only symbols: diagnostics for a file open at launch were silently
empty for the same reason, which I had wrongly put down to build settings.
Notifications now wait for the handshake and go out in the order they were
asked for.

Also: capture runs no longer take the keyboard. The screenshot is drawn
straight from the view hierarchy and never needed focus, and an app that
grabs it while somebody is typing elsewhere does not merely interrupt them —
their next keystrokes land in whatever this window has open, and get saved
there.
