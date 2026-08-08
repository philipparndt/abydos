# Draw on the display's clock instead of in the middle of parsing

`416348279` · 2026-08-01

The fire benchmark goes from 155 to 279 fps, and throughput from 16.6 to
30.1 MB/s.

Asking for a drawable waits until the display has finished with the last one.
Drawing happened inline, the moment output changed the screen, and output was
parsed on the same thread — so everything the terminal was being sent waited
for the display. Instrumented, that wait was 601 ms of every second, against
346 ms actually parsing.

A change now only notes that the screen is out of date, and a display link
draws it at the rate the display refreshes. Nothing is lost: it was already
drawing exactly sixty times a second, because that is all a drawable will
allow. Waiting is down to 2 ms a second and parsing has nearly twice the
thread.

What is left is 660 ms parsing, 25 ms building instances, 4 ms encoding. The
terminal is bound by reading its input again rather than by showing it.

The probe that found this stays, behind IDEAI_METAL_PROBE, since the next
question about this path will want the same numbers.
