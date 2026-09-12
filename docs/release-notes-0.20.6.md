# Abydos 0.20.6

## Discard Changes from the tree

Right-click a changed file or folder and *Discard Changes* puts it back the
way the last commit had it, with the same confirmation, safety-net ref and
toast as the Changes pane. A folder says how many files it will take and how
many of those are untracked. Staged-only changes and conflicts are not
offered, as in the pane.

## The sidebar panes follow the zoom

The Backlog, Structure and Scratches panes' controls now scale with the rest
of the window, as the pull-request list's already did. So do the toasts in
the corner.

## Waiting is a hairline

A pane waiting on git, GitHub, a model or a diagram shows a thin sweep under
its header instead of a spinner over its rows. The project tree's header
gains a refresh button.
