# ideai is Abydos

`0926268df` · 2026-08-06

The app, the executable, the CLI, the hook, the modules, the log folder, the
menus and the titles. Two things deliberately stay behind.

The bundle identifier does not move. macOS files the Local Network grant
against it, cannot carry one from an app's old name to its new one, and on
this beta cannot create a new one at all — so a rename that changed it would
take the network away from everything the app launches. `dev.philipparndt.ideai`
is what that grant is filed under, and the app keeps it.

Nor do the keys that state is stored under: window autosave names, split
positions and toolbar identifiers. A rename should not rearrange somebody's
desk the first time they open it.

The project folder does move, with a way back. `.abydos` is what is written;
a project that still has `.ideai` is read from it and moved across the first
time anything is written. The folder holds launch configurations somebody
committed and breakpoints they placed — data outlives the name of the program
that wrote it, and a rename that reads only the new name throws all of it
away. Verified on a project with the old folder: it moved, and both
configurations came with it.

Two things the sweep got wrong and the tests caught. SwiftPM names a resource
bundle `<package>_<target>`, so every grammar's queries were being looked for
under a package that no longer exists — Java and Kotlin stopped folding, and
the vendored grammars would have stopped colouring. And the chart the app
ships is found by that same name, which is a run in a cluster failing to find
the chart it carries.
