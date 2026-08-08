# A diagram and the lines that describe it belong on screen together

`4bbb2d267` · 2026-08-07

PlantUML files opened as text with nothing to check the text against, which
is most of the work: the diagram is what the file is for, and reading one
means looking at both halves at once. A `.puml` now opens split — source on
the left, the drawing on the right — and the drawing follows the text, both
while it is typed and when somebody else writes the file.

Nothing is bundled. PlantUML is a Java program that draws with Graphviz, and
the copy already on the machine is the one the diagrams were written against,
so whichever form of it is here is used: the `plantuml` command, a jar named
by PLANTUML_JAR, or a jar where the downloads land. Where there is none the
pane says so and says what to install, which is the one thing worth knowing
at that moment. Rendering runs off the main thread, through a pipe so nothing
is ever written beside somebody's source, and debounced because drawing means
starting a JVM.

`plantuml-lsp` is the server, discovered the same way as every other and
never installed on anybody's behalf.

Two things came out of it. A document now says when its text changed, not
only when a parser finished with it: PlantUML has no grammar here — the ones
that exist are stale and partial — so the signal every other preview follows
never fires, and a preview hung on it would draw once and never again. And a
file whose rendered form is the point of it opens in whatever mode suits it
rather than only in "preview", which is what an SVG had been getting.
