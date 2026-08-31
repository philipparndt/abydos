# Previews — delta

## ADDED Requirements

### Requirement: A video opens as a player, silent until asked

A video whose container the system decodes natively (`.mp4`, `.mov`, `.m4v`)
SHALL open in the editor area as a player showing its first frame, paused,
with the system's transport controls — a tab shaped like a picture's, with no
document and no dirty state. It SHALL NOT play sound until play is pressed,
and switching away from the tab SHALL pause it. A container the system cannot
decode keeps the binary notice and its Quick Look.

The notice's own comment concedes the point — the obvious thing to do with a
video is watch it — and then hands the watching to a floating panel that
belongs to no tab and closes on a keypress.

#### Scenario: an mp4 opens paused

- **GIVEN** a screen recording `demo.mp4`
- **WHEN** it is opened
- **THEN** the tab shows its first frame and transport controls, and nothing
  is playing

#### Scenario: switching away silences it

- **GIVEN** the video playing
- **WHEN** another tab is brought to the front
- **THEN** playback pauses, and coming back does not resume it by itself

#### Scenario: a container the system cannot play

- **GIVEN** a `capture.webm`
- **WHEN** it is opened
- **THEN** the binary notice appears as it does today, Quick Look button and
  all
