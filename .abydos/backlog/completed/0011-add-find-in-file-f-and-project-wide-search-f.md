# Add find in file (⌘F) and project-wide search (⇧⌘F)

`542b48e68` · 2026-07-30

Find in file is a strip above the editor rather than a floating panel, so it
never covers the code being searched. Matches are highlighted in place with the
current one drawn more strongly, Return and ⌘G step through with wrapping, and
the field seeds itself from the selection. Scrolling only happens when the match
is off screen, so stepping through neighbouring matches does not make the view
jump.

Project search streams results as the tree is walked, so the first hits are
usable immediately rather than after the whole walk. Results group by file with
collapsible headers, since a broad query easily returns hundreds. Excluded
directories are pruned during traversal rather than filtered afterwards — not
walking node_modules at all is the difference between a fast search and an
unusable one — and binaries are skipped with the same NUL-byte test git uses.

Both share one engine: a literal query is escaped into a regex rather than
special-cased, so case, whole-word and regex handling behave identically for
both. An unfinished regex marks the field invalid rather than reporting "no
results", which would read as a wrong answer.

140 tests.
