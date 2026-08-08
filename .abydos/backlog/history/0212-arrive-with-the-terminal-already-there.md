# Arrive with the terminal already there

`e61be2838` · 2026-08-03

Two settings, both about how a window starts.

The terminal is closed, open, or filling the window — the last for somebody
whose day starts in a shell and who reaches for the editor afterwards. Open
is the default: it is where half the work happens and ⌘J on every window is a
toll. A project left with the panel closed keeps it closed; a decision
outlives a default.

And the first terminal can attach to tmux, one session per project, so
reopening a project comes back to the panes it was left with. Only the first
— the ones opened afterwards are for the odd job that should not join the
session — and the switch is only offered where there is a tmux to attach to,
since a switch that can do nothing is worse than no switch. The session is
named after the project, with the characters tmux refuses replaced: a folder
called `v1.2` would otherwise fail to attach with a complaint about a window
index.

Also: the commit summary's placeholder sits on the line rather than above it.
A field taller than its text — which that one is, to be comfortable to click
— draws against the top otherwise.
