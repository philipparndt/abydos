# Follow the terminal into tmux, from an app nobody started in a terminal

`580c3ddcb` · 2026-08-03

Two faults, and the feature needed both fixed to work at all for anyone but
me.

tmux was looked for with `env`, and an app launched from the Finder has
almost no PATH — `/usr/bin:/bin` and the sbins — while tmux lives in
Homebrew's. So the lookup silently found nothing, and the window stayed where
it was. It worked every time I tried it, because I start the app from a
terminal. Tools are now looked for where tools actually are, and the same
search does for every other tool the app shells out to.

Then, with tmux found, the answer never came apart: the format asked for the
tty and the path separated by a tab, and tmux replaces a tab in a format with
an underscore. The field arrived as one string and was discarded as
unparseable. Since the query already filters to this client's tty, the format
now asks for the path alone and there is nothing to separate.

Checked the way it failed — the app started with a Finder's PATH, tmux in the
terminal, `cd` in a pane — and the window follows into the project again.
