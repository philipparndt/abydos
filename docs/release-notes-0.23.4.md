# Abydos 0.23.4

## A review diff can be searched, side by side, and scrolled sideways

⌘F on a pull request page opens the find bar over the diff. It matches the
code on both sides of the change, not git's prefixes or hunk headers. The page
has a switch for side by side, the same setting as View ▸ Diff. A line wider
than its column now scrolls sideways in any diff, with the line numbers staying
put; side by side, the two halves scroll together unless you unlink them.

## Stop stops everything

Stop used to end only the first thing it found running. With a run tab left
over beside a debug session, the program being debugged kept going until Stop
was pressed again. It now stops all of them.

## The same notification twice is shown once

A toast that arrives while the same one is still up no longer stacks a second
line. The one already there shows a count, ×2, and stays for another eight
seconds. Questions are never folded together.

## Open as Subproject on a `.abydos` folder

Choosing it on a project's own `.abydos` folder scoped the window to that
folder, and the run strip said "No configuration". It now opens the project
that folder belongs to.

## A cluster run links to https

The "published at" line in a cluster run's log now gives an https link. On a
Traefik cluster the route only answers on https, so the http link led nowhere.

## Pictures in the terminal with GNU coreutils

`abydos-icat` failed for every picture when GNU `mktemp` came first on the
PATH. It works with either now. Inside tmux, it says when tmux is older than
3.3 or lacks RGB for the outer terminal, instead of showing nothing.
