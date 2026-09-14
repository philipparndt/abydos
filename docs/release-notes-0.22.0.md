# Abydos 0.22.0

## A song plays beside its source

A musik-as-text `.song` opens split, the text on the left and the sound `mat`
renders from it on the right, rendered again whenever the file is saved and
never written into the project. *Mix* shows the whole song; *Stems* shows one
lane per layer with a switch to silence it. The caret lights the lane of the
track it is in, or every lane that plays the pattern it is in, and clicking a
lane's name goes to its `track` line. A save keeps playing from the same bar;
a save that does not parse keeps the last sound and shows the error over it,
and clicking that goes to the line. The lanes carry the bar grid and the
sections. Needs `mat` on the login shell's PATH (`cargo install --path
crates/mat-cli`).

## A song has a language server

`mat lsp` answers for `.song` files: problems as you type, with `mat`'s own
hints; completion of keywords, of the settings an instrument's kind takes,
of a setting's options and of the song's instrument, pattern and track names;
hover on any of them; go to an instrument, pattern or track from where it is
used; and the blocks in the structure pane. The same `mat` the pane renders
with.
