# Move and delete by word with the option key

`aa2cdcb6d` · 2026-08-01

⌥← and ⌥→ jump by word, with shift to select, ⌥⌫ and ⌥⌦ delete one, and
⌘⌫ / ⌘⌦ take the rest of the line. The editor had none of it, which is the
kind of gap you feel on every line rather than notice once.

macOS's rules, not vi's: ⌥→ goes to the end of the word ahead and ⌥← to the
start of the word behind, so holding one and then the other does not return
you where you started. That asymmetry is what every Mac text field does, and
an editor that improved on it would simply feel broken. An underscore is
part of an identifier; a run of punctuation is crossed in one step rather
than one character at a time.

The text either side of the caret is read as a window rather than the whole
document — a word is a few characters away, and asking a rope for a megabyte
to find the next space would make the arrow key slower the longer the file
got. The window grows if the answer lands on its edge.

Bound through the system's key bindings rather than by matching key codes,
so the same code answers whatever somebody has remapped these to. Verified
by pressing the actual keys.
