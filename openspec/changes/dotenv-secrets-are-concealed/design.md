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

### The cover is one width, and the rest of the line is erased

A cover fitted to its value says how long the value is, and a stepped one
still says it coarsely — reviewed and rejected. Since a dotenv value is the
rest of its line, everything from the value's start to the row's edge is
erased in the row's own background, so the line simply appears to end, and
one fixed twelve-column pill is drawn where the value began. The pill is a
shade darker than the theme's quiet text — blended toward black rather than
fixed, so a light theme's redaction is a dark pill on paper.

### The file-wide reveal lives where the eye already checks file facts

A lock on the left of the editor's status bar — the bar that names the
content type — shut while covered, open while revealed, absent for files
that conceal nothing. Pressing it is View ▸ Reveal Secrets by another door:
one state, two handles.

### One reveal, file-wide, and a click explains instead

Reviewed down from two reveals to one: the per-value click-reveal was built
and then removed, because a click is exactly the gesture a presenter makes
absentmindedly on the screen everybody is watching — the same argument that
ruled out caret-auto-reveal (an arrow-key stroll stripping covers mid-call)
and the timed reveal (a timer teaches people to screenshot). A click on a
cover now answers with a notice naming the lock. The one reveal is the
file-wide toggle, deliberately a two-step act with visible state: the lock in
the status bar and View ▸ Reveal Secrets are the same switch with two
handles, and it lasts until toggled back because somebody actively editing a
dotenv file off-call asked for exactly that. The whole feature is a setting
(on by default — the day it matters is the day nobody remembered to turn it
on), applied to open tabs the moment it flips.

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

- [A fixed-width cover misleads the eye about where the line ends while
  editing under it] → the caret stays visible over the erased zone, and the
  one-click reveal is the honest way to edit a value being looked at.
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
