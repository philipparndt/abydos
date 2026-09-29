# Abydos 0.23.3

## A new terminal starts at home, not at /

A terminal opened without a directory, and a tmux session made without one,
began at the root of the disk when Abydos was started from the Finder. They now
start in the home directory. A project's directory still wins when there is one.
