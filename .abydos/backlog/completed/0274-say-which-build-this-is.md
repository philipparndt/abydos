# Say which build this is

`6e208e8a9` · 2026-08-04

"I installed it and restarted and it is still happening" is a sentence with
two possible meanings, and there was no way to tell them apart. The bundle
carried `CFBundleVersion 1` for every build ever made.

The bundler stamps the commit count as the build number and the commit
itself beside it, so the number goes up every time and names exactly what
went in. `ideai --version` prints it, About shows it, and the bundler echoes
it as it writes:

    build 273 (c1dde9b+)

The `+` means the tree had uncommitted changes when it was built, which is
its own answer to "is this the code I am looking at".
