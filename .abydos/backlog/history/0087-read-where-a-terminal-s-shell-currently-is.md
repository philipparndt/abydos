# Read where a terminal's shell currently is

`a5fb3bda2` · 2026-08-01

Asked of the system rather than of the shell. The usual way for a terminal to
learn this is OSC 7, which the shell has to be configured to send and which
tmux keeps for itself rather than passing on. Reading it from the process
needs no configuration and works in a shell nobody has set up.

The foreground process group of the terminal is what the user is looking at,
and its working directory is the answer — except under tmux, where the client
in front of us sits wherever tmux was started and knows nothing about where
the pane has been. The server does, and will say if asked about this client
in particular, which is what makes switching tmux windows work.

It has to be asked carefully. Given a client it has never heard of, tmux does
not refuse: it answers for whichever client it spoke to last, which would put
the window into somebody else's pane. So it is asked which client answered as
well as where it is, and the answer is only taken if it is about the one that
was asked for. Found by testing exactly that case, which returned this
repository's own path.
