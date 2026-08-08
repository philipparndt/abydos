# A Makefile is not a shell script, and reading it as one showed nothing

`28f52dabe` · 2026-08-07

Makefiles were mapped to bash, which highlights a recipe and nothing around
it: the targets, the prerequisites and the three kinds of assignment are what
a Makefile is mostly made of, and all of them came out as plain text.

tree-sitter-make is vendored beside the other grammars whose own manifests
cannot be used, and `Makefile`, `GNUmakefile`, `Makefile.am`, `Makefile.in`
and `*.mk` are its own language now.
