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

## Open Questions

- Whether a lane's name should *select* the track block rather than put the
  caret on its first line. The caret is what lights the lane, so the first
  line is the honest answer to "where is this"; a selection is easy to add.
- Whether the loop should render with `--loop`, folding the tails, when the
  loop button is on. It would make the seam musical for songs that were
  written as loops, at the cost of a second render per edit.
