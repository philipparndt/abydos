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

`.song` files are coloured, by a grammar musik-as-text keeps, and `mat lsp`
answers for them: problems as you type, with `mat`'s own
hints; completion of keywords, of the settings an instrument's kind takes,
of a setting's options and of the song's instrument, pattern and track names;
hover on any of them; go to an instrument, pattern or track from where it is
used; and the blocks in the structure pane. The same `mat` the pane renders
with. Beside each line number, a small bar the length of the song lights up
where that line is heard; hover it for the bars and times. The playhead runs
through the bars, and a click or drag on one seeks the song.

## Play a song like a program

Beside each line, the time it is first heard; click it to go there, and again
for the next time. While a song plays, every line heard is marked as the
debugger marks where it stopped, and the note playing on each is lit, and a breakpoint on a line pauses the song
where that line starts. Right-click the line numbers to hide the time codes or
the bars.

Playing a song opens the debugger on it: each track is a thread named for the
pattern it plays, its stack is the note, pattern, `play` step and track, and
continue, pause, step (a bar) and stop move the song. A program already being
debugged keeps the debugger.

## A save renders only what it changed

The song pane keeps each layer between renders, so a save that changes one
pattern renders that layer and reads the rest back: about a second for a
four-minute song of ten stems, where it was ten. Muting a stem no longer
moves the playhead when the click drags a pixel. Clocks show milliseconds,
`0:31.123`.

## Export a song

Export ▸ in the song pane, or a right-click on it, writes the mix — or the mix
and its stems — as WAV, FLAC or M4A beside the song, and asks before replacing
a file. Stems now start on the same sample, so played together they sound
like the mix.

## Cut a sound file

In a sound tab, `i` and `o` mark a selection at the playhead; `k` keeps only
the selection and `⌫` deletes it, exact to the sample. Nothing is written until
⌘S, which saves in the file's own format; ⌘Z undoes a cut, and closing asks.
MP3 files can be cut and played but not saved, since macOS cannot write MP3.
