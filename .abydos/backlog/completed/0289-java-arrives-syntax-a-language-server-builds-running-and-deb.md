# Java arrives: syntax, a language server, builds, running and debugging

`707de7c69` · 2026-08-05

Work in progress committed as it stood, so a branch could be merged on top of
it. The message describes what is here; it was not written by the commit's
author.

The language side: jdtls, with the two things it cannot work out for itself.
Each project gets a data directory of its own, because jdtls keeps a compiled
index per project and will not share one; and the initialize request names the
installed JDKs, so a project targeting 17 is compiled against 17, and the
java-debug bundle, without which there is no debugging at all. Rooted at a
build file rather than at the first directory holding a `.java`, since a
project with no classpath answers nothing and explains nothing.

Around it: Maven and Gradle project models, folds for Java and Kotlin, a Java
debug adapter, and run configurations that know how to launch what those builds
produce. The dev pod learns to fetch a JRE and supervise a JVM.

`JAVA_HOME` is set for the server when the app has none, which is what a
Dock-launched app has. Unset, jdtls falls back to `/usr/bin/java` — the stub
that opens a download page.

Also here: a release publishing script, a docs landing page, and `.claude/`
added to .gitignore. That last one is not cosmetic: the agent worktrees under
it came to 6.2 GB, and nothing was stopping `git add -A` from committing all of
it.

Builds clean. 1212 tests, three failures, all of them wall-clock assertions on
a machine sitting at load average 240 — each passes on its own.
