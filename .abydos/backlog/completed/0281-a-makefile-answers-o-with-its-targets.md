# A Makefile answers ⇧⌘O with its targets

`18515e037` · 2026-08-05

The code that lists a Makefile's targets has been here since it was written,
and has never once run. It asked whether the language was `makefile` — and a
Makefile is highlighted with bash's grammar, because no grammar for make is
vendored here and bash's reads a recipe well enough. So the language is `bash`,
the question had no answer but no, and the one file in a project that is
literally a list of named things was the one file go-to-declaration came back
empty for.

Asked of the file now, by the names make itself looks for: Makefile, makefile,
GNUmakefile, and anything.mk. Those last two also get bash's highlighting,
which they had been going without.

The listing moved into the Makefile parser, where the targets come from, and
where it can be tested — it was a static function on the window controller, in
the app target, which nothing can reach. ⇧⌘O on this project's own Makefile now
offers its 22 targets, each landing on its own rule rather than on a target
further up whose name merely starts the same way.
