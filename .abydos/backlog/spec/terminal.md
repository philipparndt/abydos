# Terminal

The panes in the bottom panel: a real pseudo-terminal each, running the login
shell or one command, with tmux underneath when somebody wants their tabs to be
tmux's windows. A pane is started from the environment the app itself was
launched with, and that is where this file begins. Most of what the app was
launched with is somebody's own and is passed on untouched; a few values describe
the terminal it was launched *from* rather than the one being started, and
passing those on is how a pane comes to lie about where it is or to die before it
draws a prompt.

One requirement so far rather than an account of everything a pane does. The rest
arrives as items touch it.

## Requirement: A pane does not inherit a tmux socket path that could not exist

A shell started here is given the environment the app was launched with, and one
value in it can make tmux impossible before anything has run. `TMUX_TMPDIR` says
where tmux keeps its sockets; tmux appends `tmux-<uid>/default` to it and binds a
unix socket there, and a unix socket path is a fixed-length field — 103 bytes on
macOS, which is what the platform's `sun_path` comes to once the terminator tmux
always writes is taken off. A directory that is merely long therefore produces a
socket that cannot exist, and tmux exits saying `File name too long` about a path
nobody typed.

So the value is measured before it is passed on, against the socket it would
produce rather than against itself: resolved the way tmux resolves it, with what
tmux appends added to it. What does not fit is left out, and the shell is told
what was left out and why, in the pane and in `~/Library/Logs/Abydos/tmux.log` —
because a pane that goes straight into tmux clears its own screen.

What fits is kept, and that is as much the requirement as the refusal. A short,
valid `TMUX_TMPDIR` is somebody's choice about which tmux server their tools
share, and overruling it would put their panes somewhere their other tools cannot
see — the same mistake as ignoring their `PATH`. Nothing is substituted for a
value that is refused, either: tmux has a default of its own, and choosing a
directory here would be the same overruling by another route.

Everything else this app runs tmux for — the tab strip asking a server for its
windows, following a terminal to its pane's directory, hiding the status line,
the Claude hook writing a badge on a window — is given the same environment. Each
of those reports failure as an empty answer, so an inherited value they could not
use made them silent rather than wrong.

### Scenario: a directory too long for the socket it implies

- **Given** the app was launched from a shell with a 116-byte `TMUX_TMPDIR`
- **When** a terminal pane is opened
- **Then** the shell is started without `TMUX_TMPDIR`
- **And** the pane says which variable was left out, what the socket would have
  come to, and what the limit is

### Scenario: a directory short enough to work

- **Given** the app was launched from a shell with `TMUX_TMPDIR=/private/tmp/sockets`
- **When** a terminal pane is opened and runs tmux
- **Then** the shell still has that `TMUX_TMPDIR`
- **And** the server it reaches is the one under that directory

### Scenario: the app asking tmux something of its own

- **Given** a `TMUX_TMPDIR` whose socket path would not fit
- **When** the tab strip asks the server for its windows
- **Then** the question is asked without that `TMUX_TMPDIR`
