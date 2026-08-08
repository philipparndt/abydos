# Reading one pipe and then the other is a deadlock

`14836df9c` · 2026-08-07

The test suite hung four times in an afternoon. Sampling the stuck
process found `git push origin HEAD` blocked in write() from git's advice
printer, and the suite blocked in read() on that git's stdout — each
waiting for the other. Reading stdout to the end only returns when the
program closes it, which it does when it exits, and it cannot exit while
it is blocked writing to the pipe nobody is reading. A pipe with no
reader holds very little, and the kernel only grows one that is being
drained, so "very little" is a paragraph of advice.

Nothing about this is particular to git or to tests: the same six lines
sat in front of `helm`, `kubectl`, `make` and `plantuml`, all of them
chattier on stderr than git is, and all of them would hang the app rather
than the suite. They now share ProcessPipes, which reads both at once.
The comment that used to sit above the two reads said a full pipe buffer
was the reason they came before the wait — right about the wait, and the
reason the real bug survived being looked at.

Input is written on its own thread for the same reason from the other
end, and stdin is now always a pipe: git that inherited ours would read
from whatever the app was started with, and wait for an end that never
came.

Two things found on the way. The caller's environment was merged into the
process and then thrown away by a second assignment four lines below, so
nothing that passed one ever had it applied. And the suite now finishes
in fourteen seconds.

The deadlock tests run a real git — the bug is in the plumbing between
two processes, and a fake on this side would have gone on passing while
the suite hung. Each has a watchdog, so a return of this fails rather
than hangs. Checked by putting the sequential reads back: the stderr one
fails in thirty seconds and passes with them removed.
