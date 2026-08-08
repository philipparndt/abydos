# The terminal keeps the shell's own keys

`ad692a8a9` · 2026-08-02

⌃D ends a shell and answers k9s; ⌃R searches a shell's history; ⌃C, ⌃A, ⌃E,
⌃K, ⌃L, ⌃N, ⌃P, ⌃U, ⌃W and ⌃Z all mean something inside one. This app had
borrowed ⌃R and ⌃D for run and debug, and a menu item with a key equivalent
takes the keystroke before any view sees it — so k9s never got the one it
was being sent.

The menu items go dim while the keyboard is in a terminal, and a dim item
lets the keystroke carry on down to the view that wants it. Elsewhere they
work as before.

Also cleared the warnings that had collected: three values bound and never
used, a menu builder whose result nobody wanted, and a `#require` on
something that cannot be nil — which was hiding a test that could have said
what it meant.
