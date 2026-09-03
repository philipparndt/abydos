# Terminal — delta

## ADDED Requirements

### Requirement: A pane claims a capable terminal and does not disable the pager

The environment a pane is started with SHALL claim a capable terminal — `TERM`,
`COLORTERM` and `LANG` — and SHALL NOT set `PAGER`.

A program's behaviour when its output is long is the program's own: `git log`
opens `less` with git's `LESS=FRX`, which quits by itself when the output fits a
screen, and `man` and the rest behave as they do in every other terminal.

`PAGER` was set to `cat` here, to stop a pager hanging a pane waiting for a
keypress. That was true of a terminal that could not run a full-screen program;
this one runs `vim`, `htop`, `claude`'s own full-screen UI and tmux, and a pager
is that same class of program. The old default was also invisible where it hurt:
nothing on screen said `PAGER` had been chosen for you, so `git log` printing
everything read as this terminal being broken — which is how it was reported.

An environment given to a pane explicitly, and a `PAGER` in it, SHALL be left
alone: claiming a capable terminal is not overruling a choice. A `PAGER` the app
inherits from whatever launched it is such a choice and SHALL reach the pane
too.

A tmux server that is already running SHALL have this app's own `PAGER=cat`
taken out of its global environment at launch, and only that value. tmux hands
its global environment to every window it makes for the rest of the server's
life — weeks — so a server first started by a pane of this app goes on handing
out `cat` after the line that set it is gone. Anything other than `cat` is
somebody's own choice and is left.

#### Scenario: git log in a pane

- **GIVEN** a repository with more history than fits a screen
- **WHEN** `git log` is run in a pane
- **THEN** a pager is showing, and `q` leaves it with the prompt back

#### Scenario: a server that was started with the old value

- **GIVEN** a running tmux server whose global environment holds `PAGER=cat`
- **WHEN** the app launches
- **THEN** that variable is unset in the server, and a pane on it pages

#### Scenario: a pager somebody chose

- **GIVEN** an environment carrying `PAGER`
- **WHEN** a pane is started with it
- **THEN** that value is what the pane has
