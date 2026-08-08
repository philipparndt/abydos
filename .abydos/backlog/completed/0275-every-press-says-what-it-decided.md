# Every + press says what it decided

`6d21d86f0` · 2026-08-04

Two fixes for this have now passed their test and failed on the desk they
were written for, which means the test and the button are not doing the same
thing — and no amount of reasoning from here has found the difference.

So every press of either + appends a line to ~/Library/Logs/ideai/tmux.log:
which strip, which column, whether the panel thinks it is mirroring tmux,
the session name it resolved, and what tmux answered. There is exactly one
line that can be followed by a plain terminal, and it says so.

Written only on a press, so it costs nothing and never needs turning on —
the whole point is that it is already there the next time somebody sees this
happen.
