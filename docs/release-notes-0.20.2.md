# Abydos 0.20.2

## The terminal at a trackpad's pace

Somebody on a trackpad found the terminal scrolling far too fast — a slow drag
of one line moved ten, a flick moved hundreds — while a mouse wheel beside it
felt exactly right. The difference was the device, and the formula knew only one
of them. Whenever the pane hands a wheel event to a program — a full-screen one
such as `less` or `vim`, or anything inside a `tmux` with the mouse on, which is
most of what runs here — it counted the lines with a floor of one per event. A
wheel raises one event per notch, so that was one line per notch. A trackpad
raises around a hundred events a second, each carrying a point or two, and every
one of them became a line.

The trackpad's distance is added up now: one line per whole cell the fingers
have covered, with the fraction carried into the next event, and a gesture that
begins or reverses starts from nothing. Measured against `less` with the same
gesture replayed at both builds — ten small events and one flick — the old
build moved seventeen lines and this one moves six, which is what the fingers
covered. A mouse wheel is exactly as it was. The shell's own scrollback, which
the system scrolls, was never affected and is unchanged.

## Keys for the scrollback

There were none: every key went to the program, so a long build log could only
be read with the wheel. ⇧⇞ and ⇧⇟ page back and forward through history now,
⇧Home goes to the oldest line and ⇧End back to the prompt, where output follows
again. This is on the shell's screen only. A full-screen program still receives
the shifted keys as before, and the unshifted keys reach the program everywhere,
so `less` still pages on ⇞.

## Also in this release

**A tick on a card can be undone.** The task you just ticked from a card's tip
stays in the list for a moment, dimmed, with *Undo* at its end; ⌘Z takes it
back too while the board has the keyboard. The undo is as careful as the tick:
it writes only if the line still reads as the task that was ticked, and says so
when the file has moved on.

**Every card copies its name**, in every column, from the last entry of its
menu. And a card still being written offers the sentence that finishes it —
*write the design and the spec delta for <name>, so it is ready to apply* —
built from the documents it still lacks, for pasting into an assistant.
