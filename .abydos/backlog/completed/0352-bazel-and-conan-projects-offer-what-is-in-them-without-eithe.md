# Bazel and Conan projects offer what is in them, without either installed

`8ccd85e77` · 2026-08-07

Neither is on this machine and neither has been used by the person asking, so
both are built from what their own documentation says their command lines are,
and everything is checked against files rather than against a toolchain.

Bazel: the `*_binary` and `*_test` rules in each `BUILD` file become `bazel
run` and `bazel test` on the label they declare, run from the workspace root
where labels resolve from. Read from the file rather than asked of `bazel
query` — the query is the correct answer and it is also a build-graph load
that needs Bazel installed and can take a minute on a large repository, which
is too much to spend filling in a menu. Not a Starlark interpreter either:
what it takes is what a person takes when they open a `BUILD` file, which is
the rule name and the `name = "…"` beside it. Libraries are left out; they are
things to build, not things to start, and listing them would bury the two or
three anybody asks for.

Conan is a package manager, so there are no targets to enumerate — there are
commands, and which of them make sense depends on which file is there. A
`conanfile.py` can be installed, built, created and tested; a `conanfile.txt`
says what to fetch and holds no recipe, so offering to build it would be
offering an error message. The recipe is read for its name and never executed:
running somebody's build script to fill in a menu is not a thing to do.
