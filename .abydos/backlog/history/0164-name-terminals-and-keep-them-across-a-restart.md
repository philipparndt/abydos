# Name terminals, and keep them across a restart

`13b8feea8` · 2026-08-02

Double-clicking a terminal tab renames it in place — the name is a label on
a tab, and typing it anywhere else means finding the tab again afterwards.
Return keeps it, escape drops it, an empty name gives it back to the shell.
A renamed tab stops taking the shell's running command as its title, which
is a good default and a bad override.

Terminals now come back: what was open, what it was called and where its
shell was started go beside the project with the open files, and reopening
the project starts them again. The panel comes back with them, since
terminals restored behind a closed panel look like terminals that did not.

The session is read before the project is loaded. Opening a project touches
the editor and the panel, and anything that wrote the session on the way
past overwrote the very thing being restored — which is why the first
attempt restored nothing.

Also: the launch page no longer widens the editor area. Its fields compress
and its column stops at a readable width, so opening it leaves the navigator
where it was.
