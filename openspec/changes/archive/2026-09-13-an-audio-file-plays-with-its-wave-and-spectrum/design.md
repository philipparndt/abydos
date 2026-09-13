## Context

A video tab is `VideoFileView`: an `AVPlayerView` with inline controls, made
by `makeVideoTab` when `FilePreview.kind` says `.video`, paused on its first
frame and paused again in `viewDidMoveToWindow` when it leaves the window.
`--video-report` prints its state for a driven run.

Audio has no kind, so a `.wav` or `.mp3` opens as the binary notice. Nothing
in the app decodes audio or computes a spectrum; the app already links
AVFoundation, and Accelerate is a system framework.

The preview rules this change has to keep: *A preview nobody has looked at yet
costs nothing* (work starts when the pane is shown — `DelayedPaneView` is the
existing base for that), *A video opens as a player, silent until asked*, the
waiting strip for anything slow, and the scaled-controls library for anything
with a size.

## Goals / Non-Goals

**Goals:**

- `.wav`, `.mp3`, `.m4a`, `.aac`, `.aif`, `.aiff`, `.flac` and `.caf` open as a
  paused player with a waveform and a spectrogram.
- Seeking on the drawing, play and pause from the strip and from Space.
- A seamless loop, switched from the strip.
- Zooming and scrolling the timeline, with detail read for what is on screen.
- Playing on while another tab is in front; stopping when the tab closes.
- A one-hour recording opens without freezing the window or holding its
  samples in memory.
- Every size follows the zoom.

**Non-Goals:**

- Editing, trimming, or writing audio.
- Containers the system does not decode: `.ogg`, `.opus` in Ogg, `.wma`. They
  would need a decoder this app does not carry, and a dependency for that is a
  decision of its own.
- A live analyser of what is playing — see Open Questions.
- A loop over a selected region, markers, playback speed.
- Zooming closer than a 20 ms window: below that the detail is samples, and
  drawing them is a different view.

## Decisions

### 1. A transport strip of our own, not `AVPlayerView`

The controls are ours: a strip with play/pause and loop (`DrawnButton`s), the
time as `0:42 / 3:15`, the format, *Fit*, and the Wave / Spectrum / Both switch
(`DrawnChoice`). What plays the sound is Decision 7.

*Ruled out: `AVPlayerView` with inline controls, as the video has.* Its
scrubber is a second timeline under a waveform that is already one, and two
timelines that can disagree by a pixel are worse than one. And AppKit's
controls take their size from `controlSize`, which is the fault the
scaled-controls library exists to remove.

### 2. The drawing is the timeline

A click or a drag anywhere on the wave or the spectrogram moves the playhead
there; the playhead is one line drawn across both. Space plays and pauses,
as it does over the video. The playhead is redrawn from a periodic time
observer at 30 Hz while playing and not at all while paused.

### 3. Decoding reduces as it reads

`AVAudioFile` reads every container in the list — it is Core Audio's own
file reader, and the list is exactly what that reader accepts on macOS 14.
The list is decided in one place, `FilePreview`, and a file is read in chunks of 65,536 frames off
the main thread, and each chunk is reduced immediately:

- **Peaks:** per channel, the minimum and maximum of every 256 frames, so a
  one-hour stereo file at 44.1 kHz is about 1.24 million pairs — around
  20 MB of `Float` — rather than 1.27 GB of samples. The view draws from the
  level that gives at least one pair per point and folds pairs together for
  the width it has.
- **Spectrogram:** a mono mix, a 2,048-sample Hann window, and a hop chosen
  so the file yields at most 4,096 columns, each 1,024 magnitudes turned to
  decibels with vDSP. Drawn into a `CGImage` once, stretched to the width,
  with a logarithmic frequency axis from 20 Hz to the Nyquist frequency.

The analysis is `AudioAnalysis` in AbydosKit: the peak reduction and the
column arithmetic are pure functions over `[Float]`, tested against
synthesised sine waves — a 1 kHz tone's loudest bin is the 1 kHz bin. The
unit tests stay off the decoder: macOS reads MP3 but cannot write it, so an
MP3 fixture would have to be checked in or made by a tool the test machine
may not have. The containers are proved in the driven runs instead.

*Ruled out: reading the whole file into one buffer.* Simple, and 1.27 GB for
an hour of stereo. *Ruled out: `AVAssetReader`.* It reads the same containers,
with more ceremony for the same PCM, and `AVAudioFile` gives the frame count
up front, which the hop needs.

### 4. Mono and stereo lanes; more channels folded

One lane per channel for one or two channels. A file with more channels is
drawn as one lane of the mix, and the strip says how many channels it has —
a surround file in a repository is rare, and six lanes in a tab are
unreadable.

### 5. When it runs

The analysis starts when the pane is first shown, through `DelayedPaneView`,
and is cancelled if the tab closes first. The player exists at once, so
play works before the drawing arrives; the waiting strip sweeps at the top
edge until the peaks land, then again until the spectrogram does, which
arrives second because it costs more.

A file AVFoundation cannot decode — a truncated `.wav`, an `.mp3` that is
not one — shows what AVFoundation said, centred, in place of the drawing.

### 7. Playback through `AVAudioEngine`, so the loop has no seam

*Amended 2026-09-13, when a loop was asked for.* An `AVAudioPlayerNode` plays
the `AVAudioFile` by scheduling segments on the node's own sample timeline:
from the playhead to the end, and, while looping, a whole pass queued straight
behind it — back to back, sample-accurate, with the next pass queued each time
one is consumed so there is always one waiting. The playhead is the scheduled
start plus the node's sample time, wrapped by the file's length.

Switching the loop on or off while playing reschedules from the playhead: a
restart that can be heard once, at the press, rather than at every seam. The
engine is not started until play is pressed, so opening a tab touches no audio
device, and a driven run is muted.

*Ruled out: `AVPlayer`, seeking to zero at the end.* The seek takes tens of
milliseconds and the gap is audible on anything rhythmic, which is what loops
are for. *Ruled out: `AVPlayerLooper`.* It inserts copies of the item into a
queue player and starts them from the top, so switching it on mid-play jumps to
the start, and its seam is an item boundary rather than a sample.

A gapless seam depends on the file saying how much encoder priming to trim:
`.m4a` and `.aac` carry it, as does an MP3 with a LAME header; an MP3 without
one keeps a few milliseconds of silence at the seam. Not corrected.

### 8. Zoom and scroll

*Amended 2026-09-13.* The canvas shows a window of the file — a start and a
span, from the whole file down to 20 ms. Pinch zooms around the pointer, and
so does a vertical scroll with ⌥ held; a scroll without it pans, horizontal or
vertical; *Fit* shows the whole file. A thin bar along the bottom says which
part is on screen. The wave and the spectrogram zoom and pan together, and a
click still seeks to the moment under the pointer. While playing, a playhead
that leaves the window pages it along.

The overview is drawn stretched at once, so a zoom never shows a blank. When
the window stops moving for 150 ms, the region on screen — plus a margin of
half a window either side, so a small pan needs no read — is read again off
the main thread: peaks at the frames per pixel the width allows, and a
spectrogram of as many columns as pixels. A newer window cancels an older
read. `AudioAnalysis.read` takes the range and the two resolutions, so the
overview and the detail are the same code.

*Ruled out: one very fine overview read up front.* An hour at one peak per 16
frames is 20 million pairs, and a spectrogram fine enough to zoom into is
gigabytes; reading what is looked at costs a few hundred milliseconds per
settle.

### 9. Playing on when the tab is not in front

*Amended 2026-09-13, reversing what this change first copied from the video.*
Bringing another tab to the front keeps the sound playing; closing its tab or
its window stops it. The tab's icon becomes a speaker while it plays, so a
sound playing out of sight is one glance from being found. Opening still never
plays anything — only a press does.

### 6. Driving

`--audio-report` prints, for the front tab:
`AUDIO <name> <playing|paused> duration=<s> rate=<Hz> channels=<n> peaks=<n>
columns=<n> playhead=<s> view=<wave|spectrum|both> loop=<on|off>
window=<start>+<span>s detail=<frames per peak|none>`. `--audio-seek <s>` moves
the playhead the way a click would; `--audio-zoom <start>:<end>` sets the
window; `--audio-loop` and `--audio-play` press the buttons; `--audio-wait <s>`
waits before the report, so a loop's wrap and a background tab can be read.

## What was measured, 2026-09-13

Driven on files generated in the scratchpad, built as `de.rnd7.abydos.audio`
with an unpinned UUID. `--audio-report` waits for the analysis to land and
prints what the tab holds.

A three-second 1 kHz tone, written as each container — `afconvert` for all but
the MP3, `lame` for that:

| File | Report |
| --- | --- |
| `tone.wav`, `.aif`, `.aiff`, `.caf`, `.flac`, `.m4a`, `.mp3` | `duration=3.00 rate=44100 channels=1 lanes=1 peaks=517 columns=255` |
| `tone.aac` | `duration=3.07 … peaks=528 columns=261` — the ADTS stream's encoder padding |
| `broken.wav` (text) | `error="It is not a sound file the system can read."` |
| `voice.ogg` (Vorbis, from ffmpeg) | the binary notice with Quick Look, as before |

An eight-second stereo take — a rising sweep on the left, beats and a chord on
the right — and a ten-minute MP3 of it looped:

| Run | Report |
| --- | --- |
| `take.wav --audio-view both --audio-seek 3` | `channels=2 lanes=2 peaks=1379 columns=686 playhead=3.00 canvas=0.375 view=both info="44.1 kHz · stereo"` |
| `take.wav --audio-view wave --audio-seek 6` | `playhead=6.00 canvas=0.750 view=wave` |
| `tone.mp3 --audio-view spectrum --audio-seek 1.5` | `playhead=1.50 canvas=0.500 view=spectrum` |
| `long.mp3` | `duration=600.00 channels=2 lanes=2 peaks=103360 columns=4095` |
| `take.wav --zoom 2.0` | the same numbers; the strip, the switch and the axis labels at twice the size |

In the captures the sweep rises through the spectrogram on a logarithmic axis,
the beats are vertical bands, and the tone is a single line on the 1 kHz mark.

**Where it went differently from Decision 5.** The wave and the spectrogram
land together, not one after the other. The FFT over at most 4,096 windows
costs less than decoding the file, so a second pass for the spectrogram would
have been slower for nothing; the strip sweeps once, until both are ready.

**Where Decision 3's reader got a sentence.** Core Audio answers a text file
named `.wav` with "The operation couldn't be completed. (… error
1954115647.)", which is `typ?`. The codes a file on disk can produce — `typ?`,
`fmt?`, `dta?`, `pck?`, `perm` — are said in words; anything else keeps its
code, readably.

**The loop, the zoom and playing behind another tab**, driven after Decisions
7 to 9 were added. A driven run is muted, so what is proved is where the
playhead is, not what was heard:

| Run | Report |
| --- | --- |
| `take.wav` (8 s) `--audio-loop --audio-seek 6 --audio-play --audio-wait 4` | `playing … playhead=2.59 loop=on` — past the end and round again |
| `tone.wav` (3 s) `--audio-seek 2 --audio-play --audio-wait 2`, no loop | `paused … playhead=3.00 loop=off` — stopped at the end |
| `long.mp3` (10 min) `--audio-zoom 120:121 --audio-seek 120.5` | `window=120.000+1.000s detail=22 frames per peak` |
| `take.wav` looping, then `open:tone.flac` over it | `take.wav behind icon=speaker.wave.2.fill … playing`; `tone.flac front icon=file … paused` |
| then `close:take.wav` | `close take.wav: true — take.wav paused` |

**Found in the zoom's first capture, and fixed.** A one-second window of the
spectrogram drew about eighty columns across 1,500 points — blocks eighteen
points wide — because the hop between windows had a floor of a quarter
window. A zoomed reading asks for a floor of 64 frames; the window stays at
2,048, so the columns overlap and the second draws as many columns as the
screen has pixels.

**Space on the row**, asked for after it was built: `reveal:take.wav,space`
reports `take.wav front icon=speaker.wave.2.fill … playing` and `QUICKLOOK no
panel`; a second Space, `paused`. `reveal:clip.mp4,space` reports `video
clip.mp4 playing`, then `paused`. Neither row's menu lists Quick Look. The
panel stays for a font, a presentation and a spreadsheet, which the system
renders and no tab here shows. The video player was not muted in a driven run
before this, which a video with sound in it would have made audible; it is
now.

**The arrow keys**, asked for with the question whether ten seconds was the
step. Five was chosen: many files here are loops of two to eight seconds, where
a ten-second jump only ever lands on an end, and five is the web players' step.
⇧ steps one second, for placing the playhead closely. While looping a jump past
an end wraps, so stepping round a loop is the same gesture as listening round
it; otherwise it stops at the end. Driven on the eight-second take from 6 s:
with the loop off, → ← ⇧← ← ← gave 8.00, 3.00, 2.00, 0.00, 0.00; with it on,
→ ← ← gave 3.00, 6.00, 1.00.

**One player at a time**, asked for once sounds kept playing behind other
tabs. `OnePlayer` holds a weak claim: whichever sound or video starts takes it,
and the one that held it pauses where it was. A video takes it from its
player's own `timeControlStatus`, so its inline controls and Space inside the
player count as well as the tree. Driven with Space on rows in turn:
`take.wav` playing; `tone.flac` started, `take.wav` paused at 1.04 s;
`clip.mp4` started, `tone.flac` paused at 1.51 s of its three; `take.wav`
started again, the video paused and `take.wav` carried on from 1.04 s.

**Not heard.** Whether the seam is inaudible is the one claim a muted run
cannot make: the schedule is back to back on the node's sample timeline, which
is the mechanism, and a listen is the proof. Nor is pinch, which a driven run
cannot perform; `--audio-zoom` sets the window through the same `setWindow`
the gestures call.

## Risks / Trade-offs

- [An hour-long mp3 takes seconds to decode] → the player works before the
  drawing does, and the strip says the drawing is coming.
- [A spectrogram of 4,096 columns blurs a long file's detail] → it is an
  overview, and it is what fits a tab; zooming into a region is a non-goal
  here and a change of its own if wanted.
- [MP3 decoder padding shifts the drawing by a few milliseconds against the
  audio] → invisible at a tab's resolution; not corrected.

## Open Questions

- **What "spectrum" means.** Built as the spectrogram without an answer to
  this question. This design draws a spectrogram of the whole
  file. The request could also mean a live analyser — bars for the frequencies
  of the moment being played. The spectrogram was chosen because it can be
  read without playing anything, and it shares the wave's timeline; a live
  analyser could be added to the strip later. Worth confirming before it is
  built.
- ~~More formats.~~ Settled 2026-09-13: every container Core Audio decodes
  natively — `.wav`, `.mp3`, `.m4a`, `.aac`, `.aif`, `.aiff`, `.flac`, `.caf`.
