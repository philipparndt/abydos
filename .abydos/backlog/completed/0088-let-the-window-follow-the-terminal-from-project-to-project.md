# Let the window follow the terminal from project to project

`b8c673c01` · 2026-08-01

A control in the terminal's tab strip, on View as Follow Terminal Project,
ctrl-cmd-F. With it on, a shell that changes to another project takes the
window with it — the tree, the editors, the branch — and coming back brings
back what was open there, at the line it was left on.

Only whole projects. Moving between directories inside one changes nothing,
which is what makes this bearable to leave switched on. A submodule counts as
part of the project containing it: you step into one to change something
about the project you were already in.

Where the shell is comes from the system rather than from the shell, so
nothing has to be configured. The foreground process group's working
directory is the answer, except under tmux, where the client sits wherever
tmux was started and the server has to be asked instead — which is what makes
switching tmux windows land in the right project.

Asking tmux took two attempts. `display-message -c <client>` chooses who a
message would be shown to, not whose pane a format is about: asked about one
client while another is current, tmux answers about the current one. It said
this repository's path while the terminal was plainly in another project.
`list-clients` evaluates its format once per client, so filtering it to this
client answers about this client, and answers nothing when it is not there.

Checking happens on output and no more than four times a second: a shell that
moves prints a prompt, and one sitting idle has not gone anywhere. Following
does not take the keyboard away from the terminal that caused it.

What comes back is the tabs and their lines. A split arrangement does not:
the tabs are gathered from all the groups and restored into one.
