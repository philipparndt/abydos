# Release notes draft

For the next version's `docs/release-notes-<version>.md`, in the shape of 0.20.6.

## File ▸ New Window asks what to open

It no longer opens a copy of the window in front. A list of projects and of
the tmux server's sessions comes up; a project opens in a window of its own,
and a session opens a window on the folder it was started in with its
terminal attached. Choosing something another window has open raises that
window.

## A project is open in one window

Every way into a project raises the window that has it. A terminal that
`cd`s into a project another window has open, with following on, leaves its
window where it is and offers *Go there*.

## Two windows' terminals no longer move each other

A terminal that arrives at a tmux session another window or another terminal
program is on — at start, or
by `C-b s` or `C-b w` — gets a session of its own in the same group, named
`<session>~2`, so each window keeps its own tmux window. It goes when its
window does. Choosing a tmux window that is in front in another window —
by its tab, or with `C-b w` or `C-b n` — raises that window, and this one
stays where it was. Closing a window that leaves a terminal on another
window's moves it to a free one; with none left, it leaves tmux and says why.
