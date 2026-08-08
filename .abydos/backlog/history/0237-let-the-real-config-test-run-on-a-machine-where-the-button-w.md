# Let the real-config test run on a machine where the button was pressed

`74ec327c2` · 2026-08-04

It assumed ~/.tmux.conf had no block of ours in it, which stopped being
true the moment the button worked. The round trip now starts from that
config without our block, whichever state it is in.
