## Why

Opening a video in this editor opens a notice: the file is binary, here is a
hex viewer, here is Quick Look. The notice's own comment already concedes the
point — "the obvious thing to do with a video is watch it" — and then sends
the watching to a floating panel that covers the editor, belongs to no tab,
and closes on a keypress. A picture opens as the picture, a PDF as the
document, a mesh rendered; a video is the one rendered form still handed off.

There is no originating `.abydos/backlog` item: this comes from a direct
request, 2026-08-31.

## What Changes

- A video whose container AVFoundation plays natively (`.mp4`, `.mov`,
  `.m4v`) opens in the editor area as a playing surface with the system's
  controls — a tab like a picture's: no document, no dirty state, closed like
  any other.
- It opens paused on its first frame. Autoplay would put sound into whatever
  meeting the last change was about, uninvited.
- Switching away from the tab pauses playback: a hidden tab with a voice in
  it is a haunted window.
- Containers AVFoundation cannot decode (`.webm`, `.mkv`, `.avi`) keep
  today's notice and its Quick Look button — a player that shows a black
  rectangle with a spinner would be worse than the notice that is honest
  about it.
- `FilePreview.Kind` gains `.video`, which is the whole of the kit change;
  the dispatch that already sends pictures, PDFs and meshes to their tabs
  gains one case.

## Capabilities

### Modified Capabilities

- `previews`: gains a requirement for how a video opens — additions only,
  beside "A picture opens whole and can be looked at closely"; nothing
  existing constrains videos today.

### New Capabilities

<!-- none: the previews capability owns rendered-form opens. -->

## Impact

- **AbydosKit**: `FilePreview.Kind.video` and the extension set, with tests
  beside the existing kind tests.
- **AbydosApp**: a `VideoFileView` wrapping AVKit's `AVPlayerView`, a
  `makeVideoTab` beside `makeImageTab`/`makePdfTab`, one case in the open
  dispatch, and pause-on-tab-switch; a driver surface saying what the tab is.
- **Dependency note**: AVKit/AVFoundation are system frameworks the app
  already links transitively through AppKit's world — no third-party
  dependency, which is what the house rule is about.
- **Cost**: a player exists per open video tab and is torn down with it;
  nothing plays, decodes or ticks while the tab is not frontmost.
