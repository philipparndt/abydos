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
pattern it plays, its stack is the track, `play` step and pattern with the
pattern's lines side by side, and continue, pause, step (a bar) and stop move
the song. The Stack is now a tree of every thread for any debugger, grouped
where an adapter says and replacing the thread picker. It keeps the selection
and the open rows while a song plays under it, and takes the keyboard: click a
row, or bring the pane forward, and walk it with the arrows. A program already being
debugged keeps the debugger.

## Songs with includes

A song can `include "kit.song"` (musik-as-text e72d7e5). Saving an included file
renders the song again; its tab shows the song's playhead, heard lines and
playing notes; a breakpoint in it stops the song; and the debugger's stack goes
through the files. Opening an included file plays the song it belongs to, beside it. The song's
files share one sound: the same playhead, the same play button and the same
stem switches, so walking through them while it plays never interrupts it.

## Loops

`(A1:s A1 A2! C2~)x3` repeats notes or grid cells in a pattern line and
`repeat 4 { … }` repeats a track's steps (musik-as-text a192e0d); a looped
song sounds exactly as written out. Playing lights the written note on every
repetition, and the debugger's stack shows the `repeat` a step is in.

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

## A song is heard sooner

A song is rendered once and starts playing while it renders: the first stretch
of the mix arrives in a fraction of a second and the rest is played straight on
from it, with the stems landing at the end. It needs `mat` a5f7d05 or newer; an
older one renders the whole song before anything can be heard. A render that is
still writing takes over from a playing song only once it has passed the
playhead, so a save under a playing song is heard from the same bar. The wave
is drawn as it is written rather than at the end, and the timeline is the whole
song's from the first stretch, with what has not been rendered yet dimmed.

Songs on plugins start as fast as the rest now: with `mat` 75ac25f, harbour —
two Surge XT plugins — takes 0.20 s to its first sound instead of 11.22 s. Opening a
file a song includes no longer renders that file first.

## The stems sound like the mix

Playing the stems together now sounds like playing the mix. They used to be cut
before the master chain, so the mix had a compressor, saturation and a limiter
the stems never saw — neon's mix was 4.8 dB louder than its stems, drive's 3.7
dB, harbour's 6.5 dB quieter — and no fixed gain could stand in for something
that moves with the music. `mat` f2063b3 writes each stem through the master's
own gain curve, so the stems sum to the mix sample for sample, and the pane
plays them as they were written. It needs that `mat`; with an older one the
pane goes on turning the stems down to the limiter's ceiling as before.

## Loop a few bars while you change them

Option-click a line's bar beside the line numbers: the song loops the stretch
where that line is heard — a pattern, a `play` step, a track, a section — and
plays it. Saving while it loops renders under it, so the new sound is heard on
the next pass. Option-click the same line again to stop.

## Cut a sound file

In a sound tab, `i` and `o` mark a selection at the playhead; `k` keeps only
the selection and `⌫` deletes it, exact to the sample. Nothing is written until
⌘S, which saves in the file's own format; ⌘Z undoes a cut, and closing asks.
MP3 files can be cut and played but not saved, since macOS cannot write MP3.
