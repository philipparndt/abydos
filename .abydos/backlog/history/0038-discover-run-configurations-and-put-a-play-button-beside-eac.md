# Discover run configurations, and put a play button beside each one

`c20f5c643` · 2026-07-31

Running only worked when go.mod sat at the project root, which is wrong
for a large share of real Go repositories — the module commonly lives in
a subdirectory with the deployment files beside it. Nothing here assumes
the root is the module: it walks for modules, entry points and makefiles.

Four sources:

- IntelliJ, from .idea/runConfigurations/*.xml *and* the RunManager in
  workspace.xml, which is where the configurations IDEA creates when you
  hit run on a main function actually live.
- VS Code, from .vscode/launch.json — which is JSON with comments and
  trailing commas, so it is stripped first. The stripper leaves string
  contents alone: a URL in a value contains // and dropping the rest of
  that line would corrupt the file.
- Makefile targets, skipping the many shapes that look like targets and
  are not: .PHONY and friends, `:=` and `::=` assignments, pattern rules,
  and recipe lines, which are indented and often contain a colon.
- Go entry points, `func main` at the top level of a package main.

Only Go configurations are read from the IDE files so far; offering one
that looks runnable and is not would be worse than not listing it.

The gutter shows a play triangle on lines that have something to run,
taking the breakpoint column when both would land there — a `func main`
is more often something to run than something to stop inside, and both
do not fit in 18 points. ⌃R lists everything, grouped by source.

Paths are compared resolved. /tmp is a symlink to /private/tmp, and
`standardizedFileURL` does not resolve symlinks, so a project reached
through any symlinked directory matched nothing and showed no play
buttons at all — which is exactly what happened the first time this ran.
