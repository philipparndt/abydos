# Edit launch configurations on a page, not in a dialog

`583b6c65d` · 2026-08-02

A configuration is edited while looking at the code it runs — which package,
which arguments, which file the service reads — and a modal panel takes the
project away for as long as it is open. It is a tab now: the whole set is
listed down the left, so moving between them is one click instead of
close-reopen-choose, and what is on screen is written when a field is done
being edited.

The form is in sections, because a configuration answers three separate
questions and they are read one at a time: what to run, what it runs with,
and where. The cluster section only appears for a configuration that has a
cluster.

Files to send have a place of their own there, and files can be dropped onto
it — the file is in the project tree or the Finder already, and typing its
path again is work the pointer has done. A path inside the project is stored
relative to it, so the configuration stays the same for everybody with the
repository.

Also fixes the symbol palette telling somebody to install a TypeScript
server while they are looking at a Go file: what is missing for the project
is not what is missing for the file on screen.
