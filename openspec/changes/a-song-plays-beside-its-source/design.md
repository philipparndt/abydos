## Context

A `.song` is a block-structured text file (`docs/FORMAT.md` in musik-as-text):
`instrument`, `pattern`, `track` and `master` blocks, a keyword at column one
with indented settings. `mat render song.song -o mix.wav --stems dir/` writes
the mix, one `.wav` per *layer* and `manifest.json`, which names each layer's
file and the tracks in it, plus tempo, meter, bar length, duration and the
song's sections. Measured on `examples/drunken-sailor.song` (1:10, five tracks):
3.3 s with stems, 24-bit 48 kHz; the stems are 68.1–70.6 s long, since each
layer keeps its own tail.

The pane closest to this is Cadova's: a run, a watch on the sources, a
debounce, a deadline, the last line while it runs, and the failure text when
it fails. The player closest is the sound tab's: `AudioPlayback` over an
`AVAudioPlayerNode` for the seamless loop, `AudioCanvas` for the wave and the
spectrogram, `AudioAnalysis` for the reading.

## Goals / Non-Goals

**Goals:**

- A `.song` opens split; the sound renders when looked at and on every change
  to the file on disk, never writing into the project.
- The mix as one lane, or the stems as lanes with switches; the caret lights
  the lane its block makes; a lane's name reveals its block.
- Playing carries over a re-render; a failed render keeps the last sound.
- Bars, sections and the bar in the clock.
- `mat` missing is said in words.

**Non-Goals:**

- Syntax colouring for `.song`. There is no grammar for it and vendoring one is
  a decision of its own.
- Rendering the buffer rather than the disk. `mat` reads a path, and a song's
  samples are paths relative to it; auto-save already brings the disk to the
  buffer at every pause.
- Re-reading a zoomed window at the width's detail, as the sound tab does. A
  song's stems are a few thousand peaks each and zooming to a bar draws in
  steps; a per-stem re-read is a follow-up if wanted.
- Solo, gain, pan, or anything that writes into the song. The switches are
  the pane's, not the file's: `mute` in the song stays what `mat` renders.
- A loop rendered with `mat render --loop` (tails folded into the start). The
  loop button loops the render as it is, tail included.

## Decisions

### 1. `mat` renders the file on disk, into the temporary directory

The command is `mat render <song> -o <dir>/mix.wav --stems <dir>/stems`, run
through the login shell in the song's directory, with `<dir>` a fresh
`run-<n>` under `$TMPDIR/abydos-song/<hash of the path>/`. Fresh per run so a
render never overwrites a file the player has open; the previous run's
directory is deleted once the new playback has taken over, and the whole
hash directory when the pane goes.

The directory is named for the song *and the process* — `<hash>-<pid>` — and
a pane sweeps its song's directories whose process is gone when it opens.
Found the first afternoon: a pane deletes its directory when it goes, and a
process that is killed never gets to, so the driven runs left a gigabyte of
stems under `$TMPDIR/abydos-song`.

*Ruled out: writing beside the song.* The previews spec says a preview never
writes into the project, and a `.wav` per layer in somebody's repository is
the fault that rule is about. *Ruled out: a copy of the buffer rendered
elsewhere.* `audio "stems/Vocals.wav"` and `kick "drums.wav" at=…` resolve
against the song's directory (`resolve_load_path` in `mat-core`), so a copy in
`/tmp` renders a song with no samples.

### 2. When it renders

When the pane has been shown (`DelayedPaneView`), and then whenever the
file's size or modification date changes — FSEvents on the directory, 0.4 s
debounce, the fingerprint asked after it so a build tool writing beside the
song does not render it. A run in flight is **terminated and replaced**, which
is the opposite of Cadova's choice and for a reason Cadova gave: a package
build has a `.build` to keep consistent, a render has nothing, and the newest
text is what somebody wants to hear. A killed run's directory is deleted.

### 3. A new render takes over where the old one was

The new `AudioPlayback` is seeked to the old one's `currentSeconds`, told
whether it was looping, and played if the old was playing; then the old is
torn down. What is heard is one restart at the press of ⌘S, at the same place
in the song. *Ruled out: playing from the top.* A change to bar 30 heard from
bar 1 is thirty bars of waiting per edit.

### 4. A failed render keeps the sound

Most saves while a song is being written are not songs `mat` accepts — a line
half typed. Cadova's pane replaces the model with the compiler's message, on
the argument that a stale shape under a banner is "the same lie with a
caption". A stale sound is different: the loop somebody is writing against is
*supposed* to keep going until the next change lands, and a pane that fell
silent on every keystroke's save would be unusable for exactly the work it is
for. So the sound stays, the error is a strip over it with the first error's
message, and clicking the strip reveals the line `mat` named. Only a pane that
never had a sound — or has no `mat` — shows the failure text in the middle.

### 5. One playback, every file, volumes for switches

`AudioPlayback` now takes several files: a node per file, all started at one
host time and scheduled from the same frame; a stem shorter than the longest
is padded with a silence buffer to the same end, so a loop over stems stays in
step. The mix is voice 0 and the stems follow in the manifest's order. The
*Mix / Stems* switch and every lane switch are **volumes** — the mix at 1 and
the stems at 0, or the other way round with silenced stems at 0 — so nothing
is rescheduled and nothing loses the place. Every file decodes throughout,
which for six 24-bit files is well under a core.

*Ruled out: two playbacks, the mix's and the stems'.* Switching views would
mean stopping one and starting the other at the same frame, which is a
reschedule with a gap. *Ruled out: muting by stopping a node.* A stopped node
has no place to come back to.

### 6. `SongCanvas` beside `AudioCanvas`, not instead of it

The stems are lanes with headers, switches and a light, on one window and one
playhead; `AudioCanvas` is one file with a detail re-read. Generalising it to
several overviews would have put the song's header and switch logic into the
sound tab, which has no use for them, and the detail re-read into the song
pane, which has no per-stem reading. The wave's folding and the spectrogram's
image are `AudioCanvas`'s own statics, so the two draw a file identically; the
window arithmetic — clamp, zoom, pan, follow — is repeated, which is forty
lines and the cost of the split.

### 7. The caret's block, from a line scan

`SongSource.parse` scans the buffer for blocks at column one and reads
`layer`, `mute` and `play` under a `track`. The caret in a track lights the
track's layer; in a pattern, every layer whose track plays it; elsewhere,
nothing. It runs on every caret move, on the whole buffer — a few hundred
lines, well under a millisecond — through a second `CodeView` hook,
`onCaretLine`, because `onCaretMoved` is the status bar's and is rebound when a
tab moves between groups.

*Ruled out: `mat export`'s JSON for the tracks.* It knows the tracks and their
layers but not their lines, and it is a subprocess per caret move.

### 8. What is read for the drawing

Each render's mix and stems go through `AudioAnalysis.read` in turn, off the
main thread, the mix first since the pane opens on it; the canvas is given
the lanes after each one lands, so the mix draws while the stems are still
being read.

## Driven proof

Driven on 2026-09-13 against a copy of musik-as-text's examples under the
scratchpad, with `mat` (the checkout's own release build) on the run's `PATH`,
through `--song <steps>`. A driven run is muted, so what is proved is where
the playhead is and what the pane says, not what was heard.

`drunken-sailor.song` (1:10, five tracks, one per layer), 1.0:

| Steps | Report |
| --- | --- |
| open | `state=rendered runs=1 view=mix … duration=70.65 tempo=132 stems=5 lanes=[mix:on] info="132 bpm · 4/4 · 5 stems · peak -1.0 dBFS"` |
| `stems` | `lanes=[low_strings:on pad:on melody:on melody_octave:on drums:on]` |
| `caret:127` (in `track pad`) | `pad:on*` … `lit=[pad]` |
| `caret:56` (in `pattern verse`) | `melody:on*` … `lit=[melody]` — the one track that plays `verse` |
| `off:drums` | `drums:off` |
| `play`, 2 s | `playing playhead=2.67` |
| `seek:20`, 1 s | `playing playhead=21.74` |

The capture at that point shows five named lanes, wave over spectrum, the
`melody` lane tinted with its name in the caret's colour, the `drums` lane
greyed with a struck speaker, the bar ruler along the bottom, and the clock
reading `0:23 / 1:10 · bar 14`.

**The take-over and the failed save**, on a copy named `edited.song`:

| Steps | Report |
| --- | --- |
| `play`, 3 s | `runs=1 playing playhead=3.83` |
| `edit:137:  instrument brasss`, `rendered:2`, 1 s | `runs=2 playing playhead=6.33 error="137:14: unknown instrument 'brasss' — did you mean 'brass'?"` — the sound went on |
| `edit:137:  instrument brass`, `rendered:3`, 1 s | `runs=3 playing playhead=11.75 error=none` — the new render carried on from where the old one was |

The capture of the failed state shows the mix still playing at bar 5 under the
strip `⚠︎ 137:14: unknown instrument 'brasss' — did you mean 'brass'?`.

**`neon.song`** (3:48, ten layers, `track pad` in layer `chords`), at
`--zoom 2.0`: `duration=228.39 tempo=128 stems=10`; `caret:284` gives
`chords:on*` and `lit=[chords]`, the layer rather than the track. The capture
shows the section band (`verse`) along the top of the mix. The render took
22.8 s on this machine with `make warnings` running beside it, against 3.3 s
for the shanty — which is why the first attempt at this run reported nothing
in 34 s, and why the driver's `rendered:<n>` step polls rather than assumes.

**No `mat`**: with the checkout off the `PATH` (it is not installed on this
machine), `undertow.song` reports `state=failed runs=0` and the pane shows
`mat is not installed. In a checkout of musik-as-text, run: cargo install
--path crates/mat-cli`.

**Found in the captures, and fixed.** The strip's info label would not
compress, so at 1.0 in a half-width pane it pushed *Both* off the right edge;
it now truncates. At 2.0 in a 1280-point window the strip still overflows —
the clock with its bar, two switches and *Fit* are wider than half a pane at
twice the size — which is the sound tab's strip at 2.0 too, and left as it is.

**Found in the reports, and fixed.** The first report after a render listed no
lanes: the canvas was given its lanes only as each stem's reading landed, so
ten stems of `neon.song` were a blank pane for the seconds the reading took.
The lanes are now built at the render, named and empty, and filled as they
are read. And a pane with no `mat` never settled, so a driver waiting on it
waited for ever; it settles at once.

**Not heard.** Whether the stems stay sample-aligned across a loop's seam is
the one claim a muted run cannot make: the mechanism is one host time for
every node and silence padded to the longest, and a listen is the proof.

## Risks / Trade-offs

- [A render is CPU for seconds on every save] → it is a subprocess, costs no
  frames, and a run in flight is replaced rather than queued; a song with
  plugins renders slower and the pane says it is rendering.
- [Six stems in a pane are six short lanes] → the lanes share the height
  evenly; a song of twelve layers wants a taller pane, and *Mix* is a click.
- [The switch on the lane header is drawn, not a control] → it takes the
  theme and the zoom through the canvas; the accessibility label is the
  symbol's.
- [The restart at a re-render is audible once] → at the save, which is when
  the song changed anyway.

### 9. The last render is kept for the next pane

*Added the first evening, after the first real use:* going to another file
and back rendered the song again, twenty seconds for `neon.song`. A single
click in the tree opens a provisional tab and the next click replaces it, so
the song's pane is torn down and made again on every look elsewhere.
`SongRenderCache` keeps one render per song for the process, keyed by the
file's fingerprint, with the readings of its stems as they land; a new pane
on an unchanged file plays the last render at once and draws what was read.
The render directories are the cache's to delete now, not the pane's, and
what a process leaves when it quits is swept by the next pane to open —
which is why `staleRenderDirectories` covers every song and not only the one
being opened.

## What the stems are, and why they do not sum to the mix

*Found the first evening, listening:* the stems played together are not the
song, and a stem's level is not its level in the mix. Read off `mat`'s
render (`crates/mat-cli/src/main.rs`, `--stems`): **each stem is a solo
render of the whole pipeline** — the timeline with every other layer removed,
through the master chain: the keyed sidechain, gain, EQ, width, saturation,
compressor, clip and limiter. The linear stages commute with the sum; the
others do not. A stem's limiter and compressor see one layer's peaks rather
than the song's, so each stem is shaped and levelled on its own, and the
drums are not ducking the pad in the pad's stem because the pad's stem has no
drums to key from.

Worse than the limiter, and found by measuring: **a stem was a different
take.** `render_track` seeds a note's randomness — drift, unison spread, an
LFO's phase — from the track's index in the timeline, and a solo timeline
puts every track at index 0. Cross-correlating the old stems against the mix
gave a residual as large as the mix itself (RMS 0.149 against 0.158) and
single stems tens of milliseconds off it: the "out of sync" that was heard.

**And the players were not in step either, though they said they were.** A
`drift=` report compared each player node's clock at one render time, read
zero throughout, and was taken as proof the playback was aligned. The next
day stems were still "very slightly off". Measured with a noise file and its
inverse on two players into a silent, tapped mixer: started at one host time
as the pane did, the pair's clocks agreed and the sound did not cancel
(residual 0.499 of 0.5); started with `play()` in turn they were 512 frames
apart; started at one sample time on the output node's clock they cancelled
to 0.0000, eight trials of eight, with 1024 frames of margin or none.
`AudioPlayback` starts several files that way now, and `drift=` is gone: a
measure that cannot see the fault it was written for is worse than none.

**Fixed in `mat` the same evening** (`render_layers` in `mat-core`): one
render pass, every track rendered once as itself, mixed into its layer's
buses; each layer goes through its sends' delay and reverb, the master
sidechain keyed from the whole song, and the master's gain, EQ and width;
the mix is the layers' sum, and only then saturation, compressor, clip and
limiter. Measured on the shanty: the residual fell to RMS 0.0024 (the
limiter's doing), the lag to zero, every stem the mix's length, and the
render from 3.3 s to 2.1 s since it is one pass instead of six. The manifest
now carries `mixing` — what was applied, what was skipped, and
`sum_peak_db`, the peak of the stems' sum — and the `master` settings.

**What the pane does with it.** The stems' sum peaks above the limiter's
ceiling on any loud song (1.17 on the shanty), so at full volume the stems
view would clip in the engine. `Manifest.stemGain` turns every stem down by
the difference between `sum_peak_db` and the limiter's ceiling, never up, so
the stems view sits where the limiter would have held the mix, short of the
limiter's own squeeze. An older `mat` says nothing and the stems play at
full, as before.

### 10. Export, beside the song

*Added 2026-09-14, once `mat` wrote FLAC and M4A (4143e44).* Export ▸ in the
strip and on right-click: the mix, or the mix and its stems, as WAV (24-bit),
FLAC or M4A (AAC, 256 kbit/s). Written beside the song like a diagram's
picture — `neon.flac`, `neon stems/` — through the pane's cache, so an export
of a song just rendered costs the encode. It asks before replacing: unlike a
picture beside a diagram, a `neon.wav` beside `neon.song` may be a recording
the song plays from. A `mat` from before formats writes WAV data under any
name without complaint, so the pane asks `mat render --help` once per
executable and offers only WAV when `--bitrate` is not there.

Driven on a copy of the shanty: the menu offered all six items; `flac`,
`m4a:stems` and `wav` wrote `shanty.flac` (FLAC from a 24-bit source),
`shanty.m4a` (AAC) with five `.m4a` stems and `manifest.json` in
`shanty stems/`, and `shanty.wav` (24-bit PCM), each 70.676 s by `afinfo`.

### 11. A playing song is a program in the debugger

*Added 2026-09-15.* Asked: "while playing the debugger shall also be open,
showing the threads", then "the stack + threads are not yet shown".

Pressing play on a song opens the debug pane on a session like any other, whose
adapter lives in the app: `SongDebugAdapter`, reached through a third transport
of `DAPClient`, in-process, beside stdio and the socket. It answers the Debug
Adapter Protocol from the timeline `mat lsp` sends, which since mat 774797f
also carries every heard track and each of its `play` steps — line, pattern,
the pattern's line, start, end, pass length. So the pane, its toolbar, its
breakpoint list and the execution marker are the ones Delve drives; nothing
new was drawn for songs.

- **Threads** are the heard tracks, named for what each plays now:
  `melody · verse`, `pad · resting`, `drums · done`.
- **A stack** is the note inside the pattern inside the `play` step inside the
  track — `verse: A4:q` › `pattern verse · pass 1 of 1` › `play verse` ›
  `track melody` — each frame on its line. A grid row's cell is a note.
- **Variables**: *Now* (time, bar, pass), *Track* (track, stem, instrument,
  pattern, transpose) and *Notes*. Capitalised: the editor draws a variable's
  value beside every token of its name, and `pattern = verse` appeared after
  every `pattern` keyword in the first capture.
- **While playing**, the adapter says when a thread's name changed, and a few
  times a second at most when a note did, and the session re-reads the threads
  and the shown stack without stopping — two events a session had ignored,
  `thread` and `abydos/stackMoved`.
- **A breakpoint's stop** is the pane's own (Decision 10 of the language server
  change), told to the adapter, which stops the thread hearing the line and
  cuts the stack at it: a breakpoint on `pattern verse` stops *in* the pattern,
  before its notes.
- **The verbs** move the song: continue plays, pause pauses, a step goes to the
  next bar and stays paused, stop pauses and ends the session. The song ending
  is the program exiting. A pause with the space bar is a stop like any other.

A program already being debugged is left alone. Driven on the shanty (`debug`,
`debug:continue|pause|step|stop|thread:<n>`), 2026-09-15:

| Step | Session |
| --- | --- |
| play, 2 s in | running; five threads, `low_strings · gallop_d` … `drums · toms`; stack `gallop_d: x@41` … `track low_strings@97` |
| breakpoint on line 56, seek 0:05 | stopped (breakpoint), thread `melody` selected, marker `debug.song:56`, `verse: A4:q@56 > pattern verse · pass 1 of 1@55 > play verse@143 > track melody@136` |
| continue | running; the stack moved on to `verse: D4@56` |
| pause | stopped (pause) at 0:10.046 |
| step | stopped (step) at 0:10.909, the next bar; `low_strings · gallop_c` |
| thread 4 | `track melody_octave@148` — resting |
| stop | terminated, the song paused |

The first drive answered no threads: the `mat` on the run's PATH predated
774797f. The capture shows the pane on *melody · verse* with the four frames,
*Now*, *Track* and *Notes*, and the editor stopped on line 56.

### 12. The Stack is a tree of every thread

*Added 2026-09-15.* Asked, looking at `pattern roll_e · pass 2 of 2` with nothing
under it: "the debugger should be a tree", then "a tree for the root threads".
A list of one thread's frames behind a picker showed a song's tracks one at a
time, and two rows of a pattern sounding together as one inside the other —
`beat: x@kit.song:13 > beat: x@kit.song:14` — and a pattern between notes as a
frame with nothing in it.

The Stack is now an outline (`CallStackOutline`, over `CallTree`) for every
session, not only a song's:

- **Threads are the roots**, under a group when an adapter gives several the
  same one (`abydos/group` — a song's stem shared by more than one track). The
  picker is gone.
- **Frames nest when the adapter says** (`abydos/parentId`), outermost at the
  top and siblings in line order so a row does not move with the music; a
  debugger that says nothing keeps its list under its thread.
- **A song's stack** is the track, its `play` step, the pattern and pass, and
  every line of the pass side by side — the note sounding, or the last one,
  `subtle` (DAP's own hint) and dimmed. Ids are by place in the tree, so a row
  keeps its identity while notes come and go.
- **What opens**: the thread being shown, a thread its adapter says is busy
  (`abydos/quiet: false`, a song's playing tracks), and whatever somebody
  opened; a resting track is dimmed and shut. A Go program's goroutines say
  nothing and stay shut, so opening one is what reads its stack. The session
  keeps a stack per open thread and reads them again after a stop and, for a
  song, while it plays.
- **A new selection is scrolled to**, and followed for a moment and not once:
  the other threads' stacks, read just after a stop, opened above it and pushed
  it out of sight — measured, row 17 of 29 with rows 0–12 showing; after, rows
  5–17.

Driven on the shanty (`debug` prints the tree): playing, `low_strings` and
`drums` open to `D2: x@41`, `A2: x@42`, `D3: x@43` and `tom: x@80` beside
`kick: X@79 (subtle)`, the three resting tracks shut; stopped on line 56, every
playing track open, `verse: A4:q@56` selected and in sight, `G4:q@57`,
`A4:q@58`, `C5:q@59` subtle beside it.

### 13. Loops

*Added 2026-09-15.* Asked: "some simple loops would also help the language to
stay compact". mat a192e0d writes `(tokens)xN` in a pattern line and
`repeat N { … }` in a track, expanded by the parser so a looped song renders
sample-identical to the same song written out; 889b65c gives the grammar both.
The timeline needed nothing new: a group's note keeps its token's columns at
every repetition, so the editor lights the written token each time, and a
`repeat` line is heard across all its passes. Here the grammar is re-vendored,
and the debugger's stack puts a step inside the `repeat` blocks that hold it —
the lines between the track and the step that say `repeat` and are heard now,
nested by line order. A melodic line opening with a group, `((A1:s …`, is named
for its pattern and not for its first word.

Driven on mat's `examples/drive/` (160d1c2, eight files, the mix and seven stems
byte-identical to `examples/drive.song`), 73 s in: `[bass]` holding `bass` and
`sub`, `[lead]`, `[fx]`; `track drums@138 > repeat 4@148 > play beat_crash@149 >
pattern beat_crash@41` with its rows; the drums file's tab `song=drive.song
files=8`, playhead 77.82, cells lit inside `(X.o.x.o.)x2`.

### 14. The tree holds still, and takes the keyboard

*Added 2026-09-16.* Asked, of the Stack tree under a playing song: "the
selection is not stable during the tree update. This is very important here as
it updates constantly", "the expansion state is also not stable", "the tree does
not get the keyboard focus". Four things were wrong, each found driving it:

- **Ids by place in the list.** A pattern's row was numbered by its position
  among the rows heard, so a row changed id whenever another started or stopped
  and the tree lost track of it. A row is now `1000 + its line`, a track `0`, a
  play `1`, a pattern `2`, the repeats `5`…: a frame's id says where in the song
  it is, not where in the list.
- **`reloadData` on every message.** It drops the selection and every open row,
  and a playing song's stack arrives ten times a second. The tree now compares
  the rows it would draw with the rows it has: the same ones mean redrawing only
  those whose text changed (`reloadItem`), and nothing else moves.
- **The session re-choosing the top frame.** `refreshStack` selected the
  innermost frame each time it read a stack, which is right for a stop and wrong
  while running: it took the selection out of somebody's hands ten times a
  second. It now keeps the frame that is selected, when the new stack still has
  it. The pane, in turn, follows the session's frame only when it *moves* —
  re-asserting it on every rebuild put the selection back where it had just come
  from, a keystroke behind.
- **The keyboard.** The tree never had it: `giveKeyboard` handed it to the
  variables, and nothing took it on a click. Now a click takes it, the pane
  hands it to whichever side is showing, and walking with the arrows keeps it —
  opening a frame's line gives the keyboard to the editor, so the second ↓ was
  typing into the code.

Driven on the shanty while it plays (`debug:focus`, `debug:key:down`): the tree
has the keyboard, three ↓ land on `pattern gallop_d · pass 3 of 4` and stay
there across two updates — one of which grew the tree from 16 rows to 29 as
three tracks came in — and a fourth ↓ moves to `D2: x@41` and stays.

### 15. A few bars round and round, while the sound is changed under them

*Added 2026-09-16.* Asked: "it is hard to make one small change and directly
replay exactly this. Would be nice if we could play one section in a loop and
while playing make the changes to the sounds".

Option-click a line's bar in the gutter: the song loops the stretch where that
line is heard — the pass under the pointer, or its first — and plays it at once.
Option-click the same line again to stop looping. It is the line's own stretch
rather than a section only, so a pattern, a `play` step, a track, a section or
an instrument each loop what they are heard across, which is what "this bit"
usually means while working on a sound.

- **Playback** loops a range: `AudioPlayback.loopRange`, a stretch in seconds.
  A pass schedules to the loop's end rather than the file's, the queued pass is
  that stretch again, and the playhead wraps within it. A playhead outside the
  loop is brought to its start.
- **A render landing under it keeps it**: the loop is seconds of the song, and
  the song is what was rendered again. So a save while it plays is heard on the
  next pass, which is what this is for.
- **The pane** dims what the loop leaves out, draws its edges, and says
  `loop bars 5–6` beside the clock. The loop button turns it off, and turning
  looping off drops the range rather than keeping it for the next press.

Driven on the shanty (`loop-click:<line>[:<fraction>]`): option-clicking the
first `play verse` loops 7.27–21.82, `loop bars 5–12`, and the playhead stays
inside it; an edit to the kit rendered again (`runs=2`) with the loop still
playing; the same click again turned it off. On line 56, two bars, the playhead
went 8.94 → 7.44 → 9.58 → 8.14 → 10.35, round and round.

### 16. A render stopped before it started took the app with it

*Added 2026-09-16.* Reported: "I started with make run - but it seems to crash
(without any report) as soon as I play / navigate through the song files". There
were reports, three of them, and one was of the copy running here: an uncaught
Objective-C exception on the main queue with `showSong(at:)`, `start()` and
`render()` on the stack, and `_signalRunningTask` as the last Foundation frame.

`Process.terminate()` on a process that has not been launched raises "task not
launched". The pane stores the render in `running` and launches it a moment
later on another queue, so anything that stopped it inside that moment — a
save, a tab switch, the pane starting again on another song, which is exactly
what navigating to an included file does now — threw where nothing catches.
Stopping now asks `isRunning` first, in one place, `stopRendering`.

Reproduced before the fix by driving four song files open in quick succession:
three runs, three crashes, no report from the pane. After it: three runs, the
song rendered and played in each, and no new crash report.

The 3D and PlantUML panes store and launch their process the same way and had
the same two lines; they ask now too.

### 17. The mix before the stems, and no render of a file that is not a song

*Added 2026-09-16.* Asked: "it looks like we are rendering again when navigating
to files of the same projects, also it seems that we always need the complete
rendering till something is shown".

- **A file of a song renders nothing of its own.** Opening one started a render
  of it before the server had said which song it belongs to — a kit, twenty
  seconds, thrown away the moment the answer arrived. The pane now holds its
  first render for a moment (1.5 s) when a file's song is not yet known, and
  the timeline releases it: `showSong(at:)` for another song, `songIsKnown()`
  for its own. Driven: opening `drums.song` of the drive example renders
  nothing (`runs=0`) and plays the song.
- **The mix is played while the stems are still being written.** `mat` writes
  the mix, then a stem per layer, then the manifest — and the manifest was what
  the pane waited for. It now watches the mix while the render runs and takes
  it as soon as it has stopped growing: one lane, no bar grid, and the song
  plays. The whole render replaces it a moment later, from the same place,
  through the same path a save takes. Driven on a fresh copy of the drive
  example: the pane has the song's 3:41 with `tempo=0 stems=0` while `mat` is
  still running, and `tempo=133 stems=7` when it lands.

**And the first bars before the song.** "Ideally we can start early before the
render is even complete": `mat` f684cab renders a stretch of bars, so a pane
with nothing to play renders bars 1–8 first — half a second — plays that, and
renders the whole song behind it. The preview goes through the same path a
render lands by, marked partial: nothing is kept in the cache for it, and the
whole song replaces it when it arrives.

Measured on the drive example (3:41, seven layers), nothing cached, load 15:

| Render | Wall clock |
| --- | --- |
| bars 1–8 | 0.42 s |
| the whole song | 6.61 s |

Driven on a copy nothing had rendered: the pane showed 19.1 s of song with
seven stems while `mat` was still going, and 3:39 when it landed.

**The pane's own size.** These went in beside three other splits: the files a
song is made of and their watch (`SongSources`), where a breakpoint stopped it
(`SongBreakpointStops`), whether the first render has landed (`SongSettled`),
what has been read of the render to draw it (`SongOverviews`), and running
`mat` itself with its debounce, watchdog and fingerprint (`SongRenderRun`). The
pane is 1039 lines from 1119, and what left it is state.

### 18. The debugger's state is behind a lock

*Added 2026-09-16.* Two crashes came in a day, and both are the same thing: a
`DebugSession` is written by the task that read the adapter's answer — a
cooperative thread — and read on the main thread by the pane that draws it, ten
times a second while a song plays. A Swift collection read while it is being
written does not answer wrongly; it crashes. The first looked like a dictionary
with a string where a collection belonged, inside a launch; the second was
`EXC_BAD_ACCESS` in `swift_release_dealloc` with `StackFrame`'s value witnesses
and `refreshStack` on the stack.

The threads, the stack, the stack per thread, the scopes, the inline values,
the selected thread and frame and the breakpoints are now behind one lock in
the session. The right answer is for the session to be main-actor, which is a
change across the debugger and every adapter it drives; the lock is what makes
the collections safe today.

## Open Questions

- Whether a lane's name should *select* the track block rather than put the
  caret on its first line. The caret is what lights the lane, so the first
  line is the honest answer to "where is this"; a selection is easy to add.
- Whether the loop should render with `--loop`, folding the tails, when the
  loop button is on. It would make the seam musical for songs that were
  written as loops, at the cost of a second render per edit.
