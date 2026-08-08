# Every Make goal can become a launch configuration, and be jumped to

`7d2633c17` · 2026-08-04

Run ▸ New from Make goal… lists every goal every Makefile in the project
defines, and turns the chosen one into a launch configuration to run, edit
and keep.

Every one, unlike the list offered beside the play button. That list leaves
out `help`, `clean`, `install` and the rest because suggesting them is
noise — which is why `make install` was nowhere to be found in a project
whose Makefile plainly defines it. Somebody who opens this dialog has said
which goal they want, and refusing to show `install` because it is usually
uninteresting is refusing the thing they came for.

⌘⇧O works in a Makefile too. It has no language server, and the grammar it
borrows for colour is bash's, which knows nothing about targets — so the
one kind of file in a project that is nothing but a list of named things
was the one kind this could not list. The Makefile parser already reads
them; the line each was written on is found by looking for its own rule,
since the parser reads a Makefile for what it runs and has no reason to
record where.

The rain also falls thicker: a column restarted a screen above the top,
which at any one moment left most of them empty. A quarter of a screen, and
it is rain.
