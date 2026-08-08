# The completed backlog comes from the history, not from a second telling

`2017d6398` · 2026-08-08

Every commit in this project says what it changed and why, so the history
already is the record of what was done — 384 of them, most with more to
say than a title. Keeping a hand-written summary beside that is keeping a
second copy that will disagree with the first.

So `completed/` is generated from `git log`, one file per commit, oldest
first, and can be rebuilt at any time. Nothing is written there by hand,
because a file that could not be regenerated would quietly become the
only copy of something.

`open/` and `in-progress/` stay hand-written, and stay the interesting
half: each carries what has already been ruled out as well as what the
task is.

`history.md` is gone. It was every request recovered from the session
transcripts, which sounded useful and was mostly noise beside this: the
commits say what was actually done, in the author's words, at the time.
