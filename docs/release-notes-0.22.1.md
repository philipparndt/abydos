# Abydos 0.22.1

## The terminal goes back to the tmux session it was in

A project's terminal starts in a session named after the project's folder, and
it used to start there every time, even when it had been moved to another
session with `C-b s` or the session tag — so a long-lived session with the
work in it was a menu away each morning, and a fresh one-window session was
left behind each time. The session the terminal was looking at when the
project was last left is now remembered beside the window, in the project's
`.abydos`, and is the one attached to on the next open, so long as the server
still has it. One that has gone is not made again; the project's own is.

## Close several tmux sessions at once

The session tag's menu has *Close Sessions…*: every session on the server with
a box beside it and how many windows it holds, *Select All* for the lot, and
*Close* kills the ticked ones. The session this window's tabs are showing is
listed but cannot be ticked — closing its last window is how that one goes.

## A song shows its patterns and notes

The song pane's drawing choice has *Notes* beside *Wave*, *Spectrum* and
*Both*: every `play` line as a region named after its pattern, with its
repeats marked and the notes inside it, the way a DAW shows a song. Zoomed out
it is the regions; closer, the notes on their pitches, drums a row per sound;
closer still, their names and a key strip. The caret in a `pattern` lights
every region of it, clicking a region goes to its `play` line and ⌥-clicking
to the pattern. It needs a `mat` whose `export` has regions (c036a81); an
older one draws the notes without them.

## A song plays straight through while it renders

A song started before its render has finished now plays through its first
seconds without stopping and starting at every stretch that arrives, and the
stems join without a gap when the render lands. Switching between *Mix* and
*Stems*, or silencing a stem, fades over 80 ms instead of clicking.

## A song's tab stays the song's

Going between a song's files no longer starts its render again or stops the
sound, even when another open song includes the same files. The tab keeps the
song's name, a song that has been played keeps its tab, and the row above the
text reads `♪ ember.song › drums.song ⌄` — the song, then the file being
edited, with the menu of the song's files on it.

## Moving a playing song no longer crashes the app

A song whose folder was moved or deleted while it played took Abydos down at
its next render. The render now fails with a line saying the folder is gone,
and the sound plays on.
