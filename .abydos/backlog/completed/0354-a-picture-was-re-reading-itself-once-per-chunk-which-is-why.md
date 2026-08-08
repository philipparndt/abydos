# A picture was re-reading itself once per chunk, which is why it took minutes

`90e12a720` · 2026-08-07

The protocol wants the payload in four-kilobyte pieces, and the way it was cut
into them was to take a slice of a shell variable per piece. `cut -c` re-scans
the string from the start every time, so a five-megabyte picture — seven
megabytes of base64, eighteen hundred pieces — spent five minutes reading
itself, and spawned eighteen hundred processes doing it. `fold` splits it once.

Five minutes to 1.75 seconds, measured on the same file.

Two other things while in there. The converted copy of a JPEG was deleted
before its size was asked for, so the answer was nothing and every non-PNG
came out the width of the window rather than its own size; it is deleted after
now. And the diagram pane's spinner sat exactly where its message is drawn, so
the two overlapped — the spinner is above the text, and the text sits in the
same place whether or not one is turning.
