## Context

`CodeView` draws everything itself: per visible row, bands (line background, find matches, selection occurrences), then `drawLine` (text, selection, current match), then the gutter and the caret. The editor spec states that order and requires any new band to take a stated place in it. Range-to-rectangle machinery exists — `searchHighlights` turns character ranges into row-local `NSRect`s. The app has a presentation mode (`Settings.presenting`), but macOS offers no reliable "this window is being captured" signal to a third-party app, and the file at risk is usually open *before* the share starts.

## Goals / Non-Goals

**Goals:**

- Values in dotenv-shaped files unreadable by default, on screen and in
  screenshots, from the moment the file opens.
- Reveal only by explicit action — a click on the one cover, or a per-file
  toggle — never by the caret merely arriving.
- Editing works without revealing: typing under a cover stays covered.
- The classification is kit code, tested against fixture lines.

**Non-Goals:**

- No capture detection and no tie to presentation mode: the first is not
  reliably possible, and the second is not when screens actually get shared.
  Default-on is the design.
- No content-based secret detection in arbitrary files (entropy heuristics are
  false positives waiting to interrupt somebody's JSON). The name shapes are
  the contract; if somebody wants `credentials.yaml` one day, the kit type is
  where the shape is added.
- The diff view and the terminal show what they show. A `.env` diff on screen
  is rarer than an open `.env`, and the terminal echoing `cat .env` is the
  shell's own output — both are their own changes if they are wanted.
- No re-keying of anything: concealment is presentation, not security at rest.

## Decisions

### A cover drawn over the text, not a transformation of it

The value's glyphs are drawn as they are and a solid rounded rectangle is
painted over them, using the same range-to-rect machinery the find bands use.
Nothing about the document changes: offsets, caret positions, undo, find and
copy all see the real text. Ruled out: substituting bullet glyphs at layout
time — every offset the editor works in would need a parallel mapping, which
is the class of bookkeeping this editor deliberately avoids; and a screenshot
of a solid pill leaks nothing either way. The cover is opaque (no alpha): a
band that merely tints leaves glyph shapes readable on a bright projector.

### The cover's place in the paint order is stated

Over the text, the selection and every match band — a redaction that anything
can be painted over is not one — and under the caret, so the editing position
stays visible. The editor spec's paint-order requirement is modified to say
so; that requirement exists precisely so this decision is written down rather
than layered where it was convenient.

### Reveal is explicit, twice over, and undone by leaving

Per the request's refinement: nothing reveals on caret arrival. A click on a
cover reveals that one value, and the reveal lasts while the caret stays on
that line — leaving the line conceals it again, so a revealed value cannot be
forgotten open. View ▸ Reveal Secrets toggles the whole file and says so in
the menu state; it lasts until toggled back, because somebody actively editing
a dotenv file off-call asked for exactly that. Ruled out: caret-auto-reveal —
an arrow-key stroll through the file would strip every cover mid-call. Ruled
out: a timed reveal — a timer taking a value off screen mid-read teaches
people to screenshot it instead.

### Typing stays covered

A keystroke into a covered value updates the document and the cover widens
with the value; the glyphs never show. The password field is the precedent,
and the screen-share is exactly where a freshly pasted key must not appear.
The caret remains visible over the cover, so the editing position is never a
guess.

### The kit decides what conceals and where

`DotenvSecrets.conceals(fileNamed:)` — the name shapes `.env`, `.env.*`,
`*.env`, and `*.dec`, the file a SOPS-style decrypt leaves beside its
encrypted original: decrypted-on-purpose is the most secret-laden file a
screen can show — and `DotenvSecrets.valueRange(inLine:)` — the value of a
`KEY=VALUE` line: after the first `=`, `export ` prefixes skipped, quotes
included in the cover, comments and `=`-less lines nil. In AbydosKit, because
that is where every testable decision lives, and this one is all edge cases.

## Risks / Trade-offs

- [A wide value's cover says how long the secret is] → the cover is drawn at
  a minimum width and rounded to a step, so length leaks only coarsely; the
  alternative of fixed-width covers misleads the eye about where the line
  ends while editing.
- [Somebody's `.env` holds non-secrets (`NODE_ENV=production`)] → the cover
  costs one click to look under; the reverse mistake costs a key. Default-on
  with cheap reveal is the right asymmetry.
- [Print/preview paths that reuse CodeView rendering inherit covers] → they
  should: anything that draws the file draws it covered.
- [A driven screenshot of a dotenv file now shows pills] → deliberate, and
  the driven proof of the whole feature.

## Open Questions

- Whether other well-known shapes (`*.pem`, `id_rsa`, `credentials`) join
  `conceals(fileNamed:)` is left until asked; the seam is one function.
