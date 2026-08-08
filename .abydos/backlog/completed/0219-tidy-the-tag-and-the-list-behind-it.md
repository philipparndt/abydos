# Tidy the tag and the list behind it

`eef515fc5` · 2026-08-03

The chevron is drawn rather than typed. A `⌄` is a character with a baseline
of its own and sits low beside anything else; a two-line path sits where it
is put, and the text and the chevron are laid out as one thing so the pair is
centred in the pill rather than the text alone.

The menu had a name and a count running together on every row, at every
length, which reads as a jumble. Names in one column and counts in another,
on a tab stop, with the counts dimmed.

And the sessions come back in the order tmux cycles through them — oldest
first, which is what `C-b (` and `C-b )` walk — rather than the alphabetical
order `list-sessions` prints, which puts a session called `0` in front of
everything however long ago it was made.
