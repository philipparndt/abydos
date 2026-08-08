# Give the tmux settings a card of their own, and test the hook for real

`97678e4c6` · 2026-08-04

The three tmux switches now sit inside a rounded card with a heading and
a sentence, which is what "these belong together" looks like here — a
heading and a gap were not saying it. A group holds its rows rather than
marking where one starts: the first version had no end and swallowed
every setting that came after it.

And the hook has live tests now, run as Claude Code runs it — the built
binary, a real tmux session, the badge read back from the window option
after each event. Both badge bugs lived in that plumbing rather than in
the mapping the unit tests already covered: the sequence prompt →
subagent → stop → straggling subagent → nudge → next prompt is now a
test, as are a permission prompt after a finished turn and a session
ending taking its badge with it.
