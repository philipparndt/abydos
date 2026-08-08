# Write down the moments the main thread stops answering

`5f3281c1d` · 2026-08-03

Typing that "feels slow" is nearly always the main thread being busy for
a few hundred milliseconds, and by the time it is noticed whatever did it
has finished and left nothing behind. A thread of its own now pings the
main queue ten times a second and logs every ping that came back late,
with what the app said it was doing — terminal parse, terminal draw,
navigator reload, history graph, tmux tabs — read at the threshold, while
the work is still running rather than after it has unmarked itself.

Late pings only, so an idle app writes nothing:
~/Library/Logs/ideai/stalls.log.
