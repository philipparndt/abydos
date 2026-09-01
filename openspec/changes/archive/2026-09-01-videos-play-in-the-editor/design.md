## Context

Non-text files already have a settled shape: `FilePreview.kind(for:)` classifies by extension, and the editor's open dispatch hands each kind its own tab — `ImageFileView`, `PdfFileView`, the model viewer — with `document: nil` and `previewMode = .preview`, so ⌘W, the tab strip and previews behave without a `TextDocument` pretending to exist. A video falls through all of it to the binary notice, whose Quick Look button is today's answer. The notice stays the answer for what cannot be played.

## Goals / Non-Goals

**Goals:**

- An `.mp4`/`.mov`/`.m4v` opens as a player in a tab, first frame visible,
  paused, with the system's transport controls.
- Sound never starts by itself: not on open, not on a tab somebody switched
  away from.
- The classification is one kit case with tests; the app side follows the
  picture tab's precedent exactly.

**Non-Goals:**

- No decoding beyond what AVFoundation does natively. `.webm`, `.mkv` and
  `.avi` keep the notice: shipping a decoder is a dependency with a written
  reason this change does not have, and a player that spins over a black
  rectangle is dishonest about why.
- No editing, trimming, or export — the tab is for watching what a screen
  recording or a test capture produced.
- No thumbnail strips in the project tree, no hover previews.
- Audio files are a neighbouring question, left until asked; the seam is the
  same enum.

## Decisions

### AVKit's player view, not a hand-rolled surface

`VideoFileView` wraps `AVPlayerView` with its inline controls. The system
view brings scrubbing, volume, full-screen, picture-in-picture and the
keyboard's space-to-play for free, and it is what every user's muscle memory
expects. Ruled out: drawing frames into a custom view the way the editor
draws everything else — the editor's custom drawing exists for text
invariants a player does not have, and rebuilding transport controls is a
project, not a task.

### Paused on the first frame, always

The player loads the asset and shows frame one; nothing plays until the
person presses play. Autoplay on open is ruled out twice over: an editor tab
is often opened mid-meeting (the previous change exists because screens get
shared), and a preview-mode single-click open that starts talking is a jump
scare, not a preview.

### Switching away pauses

The tab losing frontmost pauses the player (and keeps its position). A tab
that keeps playing invisibly is audio with no visible source — the haunted
window. Coming back does not resume by itself, for the same reason opening
does not.

### The honest extension set

`mp4`, `mov`, `m4v` — the containers AVFoundation decodes natively on every
supported macOS. Ruled out: claiming `webm`/`mkv`/`avi` and letting AVKit
fail at runtime — the notice with Quick Look is a better answer than a
player that cannot say why it is black. The set lives in the kit beside the
image extensions, where the next container joins by one string when Apple's
decoder does.

### The tab is the picture tab's shape

`document: nil`, `previewMode = .preview`, torn down with the tab, external
changes handled the way `ImageFileView` handles them. No new tab machinery:
the whole point of the existing dispatch is that a new rendered kind is one
case and one view.

## Risks / Trade-offs

- [A large video held by an open tab keeps a decoder alive] → one player per
  open tab, released on close; a paused player's cost is memory for the
  decode pipeline, which is what having the file open means.
- [Space already means something in the editor] → the player view has the
  keyboard only when the tab does, which is the same contract every other
  preview tab keeps.
- [A corrupt or truncated file] → `AVPlayerView` reports its own error state
  over the frame area; the tab stays honest without new UI.

## Open Questions

- Whether the driven harness needs a generated fixture clip (a one-second
  solid-colour `mp4` written by `AVAssetWriter` in the scratch repository) or
  a checked-in tiny fixture is left to implementation; nothing else in
  `Tests/Fixtures` is binary today, which argues for generating it.
