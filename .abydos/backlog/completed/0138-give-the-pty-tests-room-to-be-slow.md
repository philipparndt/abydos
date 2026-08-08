# Give the pty tests room to be slow

`f19c51547` · 2026-08-01

They wait on a real process, and the suite runs in parallel: a machine
with every core busy can take seconds to get round to a /bin/echo that
normally answers instantly. One five-second wait ran out and failed a
test that was working.
