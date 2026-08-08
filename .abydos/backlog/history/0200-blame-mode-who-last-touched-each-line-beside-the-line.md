# Blame mode: who last touched each line, beside the line

`cb7049c85` · 2026-08-03

⌥⌘B on a file, and a column appears in front of the gutter: the author and
how long ago, once per commit rather than once per line. Forty lines from one
change say so once — repeating the same name forty times makes the reader
work out what the eye should simply see.

A name that does not fit gives way before the date does: "Katherine Johnson"
becomes "K. Johnson", because the surname is what identifies somebody and the
age is what you were looking for. A line still being written says
"Uncommitted", in the colour the rest of the app uses for a change nobody has
kept — attributing it to whoever last committed there would be a lie. Click a
name and it says what that commit was.

Read from `git blame --line-porcelain`, which repeats the header for every
line rather than abbreviating after the first: more output, and no state to
carry between lines, which is where the subtle bugs in a blame parser live.

Per editor, not per window: blame is something turned on to answer a question
about one file, and a column of names beside everything else afterwards is
not what was asked for.
