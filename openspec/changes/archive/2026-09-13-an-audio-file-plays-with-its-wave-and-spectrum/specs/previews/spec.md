# Previews

## ADDED Requirements

### Requirement: An audio file opens as a player with its wave and its spectrum

An audio file SHALL open in the editor area as a player, paused at the start,
with no document and no dirty state, when its container is one the system
decodes natively (`.wav`, `.mp3`, `.m4a`, `.aac`, `.aif`, `.aiff`, `.flac`,
`.caf`). A container the system cannot decode SHALL keep the binary notice and
its Quick Look. The tab SHALL show the file's
waveform — one lane per channel for mono and stereo — and a spectrogram of the
whole file, selectable as the wave, the spectrum, or both, sharing one
playhead. It SHALL NOT play until play is pressed or Space is typed. It SHALL
keep playing when another tab is brought to the front, SHALL stop when its tab
or window is closed, and its tab SHALL show that it is playing. A loop button
SHALL play the file repeatedly with no gap added at the seam. The wave and the
spectrogram SHALL zoom and scroll together, and zoomed in SHALL be read again
at the detail the width allows. A click or drag on the drawing SHALL move the
playhead to the moment under the pointer. Starting a sound or a video SHALL pause any other that is playing, in any tab
or window. In the sound's tab, ← and → SHALL move the
playhead five seconds back or forward, and with ⇧ one second, wrapping round
while looping and stopping at the ends otherwise. Space on a sound's or a video's row
in the project tree SHALL play or pause its tab rather than open Quick Look,
and Quick Look SHALL NOT be offered for a file whose tab already shows it — a
picture, a PDF, a sound or a video. Decoding and analysis SHALL run off the main thread, begin
only when the tab is first shown, and show the waiting strip until they land;
play SHALL work before they do. A file that cannot be decoded SHALL show what
the decoder said in place of the drawing.

Asked for 2026-09-13: sound files opened as the binary notice, while video
already played in a tab.

#### Scenario: a wav opens paused, drawn

- **GIVEN** a stereo recording `take.wav`
- **WHEN** it is opened
- **THEN** the tab shows two lanes of waveform and a playhead at the start,
  and nothing is playing

#### Scenario: seeking on the wave

- **GIVEN** `take.wav` open and paused
- **WHEN** the wave is clicked halfway across
- **THEN** the playhead moves to half the duration, and pressing play starts
  from there

#### Scenario: the spectrum

- **GIVEN** a file holding a 1 kHz tone
- **WHEN** the tab is switched to the spectrum
- **THEN** the loudest band is drawn at 1 kHz on the frequency axis, and the
  playhead is at the same moment it was over the wave

#### Scenario: leaving the tab

- **GIVEN** an `.mp3` playing
- **WHEN** another tab is brought to the front
- **THEN** it keeps playing, and its tab shows a speaker

#### Scenario: closing the tab

- **GIVEN** an `.mp3` playing in a tab that is not in front
- **WHEN** that tab is closed
- **THEN** the sound stops

#### Scenario: one at a time

- **GIVEN** `take.wav` playing in a tab that is not in front
- **WHEN** `clip.mp4` is played
- **THEN** `take.wav` pauses where it was, and its tab stops showing the speaker

#### Scenario: jumping with the arrow keys

- **GIVEN** an eight-second loop in its tab with the playhead at 6 s
- **WHEN** → is pressed with the loop off, and again with it on
- **THEN** the playhead stops at 8 s the first time, and wraps to 3 s the second

#### Scenario: Space on the row

- **GIVEN** `take.wav` selected in the project tree, with the keyboard there
- **WHEN** Space is pressed, and pressed again
- **THEN** its tab plays and then pauses, and no Quick Look panel opens; a
  video's row does the same

#### Scenario: a seamless loop

- **GIVEN** a two-second drum loop with the loop button on
- **WHEN** it plays past the end
- **THEN** it carries on from the start with no gap, and the playhead wraps

#### Scenario: zooming in on a moment

- **GIVEN** a ten-minute recording
- **WHEN** the timeline is zoomed to the second between 2:00 and 2:01
- **THEN** the wave and the spectrum show that second, read again at the
  width's detail, and scrolling moves along the recording from there

#### Scenario: a long recording

- **GIVEN** an hour-long `.mp3`
- **WHEN** it is opened
- **THEN** the window stays responsive, play works at once, and the wave and
  then the spectrum arrive under the waiting strip

#### Scenario: every natively decoded container

- **GIVEN** the same tone saved as `.wav`, `.mp3`, `.m4a`, `.aac`, `.aiff`,
  `.flac` and `.caf`
- **WHEN** each is opened
- **THEN** each opens as the player with its wave, and their durations agree
  to within the encoder's padding

#### Scenario: a container the system cannot play

- **GIVEN** a `voice.ogg`
- **WHEN** it is opened
- **THEN** the binary notice appears as it does today, Quick Look button and
  all

#### Scenario: a file that is not what its name says

- **GIVEN** a `broken.wav` holding text
- **WHEN** it is opened
- **THEN** the tab says the file could not be decoded, in the decoder's words,
  and draws no wave
