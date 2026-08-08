# A file listed relative to the project is a file this app wrote

`199130a94` · 2026-08-06

`entry(for:in:)` stores anything inside the project relative to it on
purpose: a launch configuration is committed and shared, and
`/Users/somebody/...` is not shareable. Reading it back resolved that path
against this process's own directory, where it names nothing, so the
transfer was dropped without a word.

What that looks like is not a missing file. The pod starts with no
configuration, and the program says the argument it needs is missing — about
a file the configuration does list, sitting in the project where it belongs.
Every test here spelled its entries out in full, which is why the form this
app writes itself was the one nobody checked.

Canonical, so the file named by an argument and the same file listed here
are still recognised as one and sent once.
