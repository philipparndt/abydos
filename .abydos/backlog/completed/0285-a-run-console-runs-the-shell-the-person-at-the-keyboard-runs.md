# A run console runs the shell the person at the keyboard runs

`47df63738` · 2026-08-05

`make run` printed `pnpm: command not found` for a pnpm that `which` finds one
tab away, in the same project, on the same machine.

The console ran `/bin/sh -lc`, which reads `/etc/profile` and `~/.profile` and
nothing else. Almost nobody's tools are there any more: fnm, nvm, mise, asdf,
pyenv and pnpm all install themselves into `~/.zshrc`, which only an interactive
shell reads. fnm goes further and puts its binaries in a directory belonging to
one shell session — `~/.local/state/fnm_multishells/<pid>_<timestamp>/bin` —
created when that shell starts and deleted when it exits.

Which is why this looked like a regression and was not one. The command has
been built this way since run configurations were added. What decides whether
it works is how the app was launched: from a terminal it inherits that shell's
PATH and pnpm is found, until that terminal is closed and the directory in the
PATH stops existing. From the Dock there was never anything to inherit. The
same `make run` works in the morning and fails in the afternoon with nothing
changed anywhere.

A terminal pane has always run the user's own shell, logged in and interactive,
which is exactly why typing `make run` into one works. A run console now runs
the same shell the same way, so pressing Run and typing it out reach the same
tools. It is a pty, so interactive is what it honestly is, and the prompt is
never drawn: the shell is given a command and exits after it. `sh` and `dash`
keep `-lc`, having no interactive-only startup file to read.

Checked with the app launched the way the Dock launches it — PATH of
`/usr/bin:/bin:/usr/sbin:/sbin` and nothing else. Before: `make: pnpm: No such
file or directory`. After: the version prints and the target finishes.
