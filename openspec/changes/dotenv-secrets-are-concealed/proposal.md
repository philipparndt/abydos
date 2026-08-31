## Why

Screens get shared — a Teams call, a review, a demo — and the `.env` file that
was open a minute earlier, or gets opened during the call to check a name, puts
its API keys in front of everyone watching. The reflex of closing the file
comes after the leak, and rotating a key costs an afternoon. macOS gives an app
no reliable signal that its window is being captured, so the protection cannot
wait for one: the values have to be unreadable *by default*, and readable only
when somebody explicitly asks — which is how the request was refined: "they
should only be shown with an explicit action."

There is no originating `.abydos/backlog` item: this comes from a direct
request, 2026-08-31.

## What Changes

- In files shaped like dotenv files (`.env`, `.env.*`, `*.env`) and in
  decrypted secret files (`*.dec`, the shape a SOPS-style decrypt leaves
  behind), the value of
  every `KEY=VALUE` line is drawn under a redaction cover — a solid pill where
  the value would be. Comments, blank lines and lines without `=` are shown as
  they are.
- Revealing is an explicit action, and only that: clicking a cover reveals
  that one value while the caret stays on its line; View ▸ Reveal Secrets
  reveals the whole file until toggled back. Nothing reveals because the caret
  merely arrived.
- Typing into a covered value stays covered, the way a password field works —
  the screen is exactly where the new key must not appear.
- Concealment is a rendering, not a transformation: offsets, caret, undo and
  copy are untouched — copying a value copies the value, which is a deliberate
  act that puts nothing on screen.
- The detection and the value ranges live in AbydosKit, testable without a
  window.

## Capabilities

### New Capabilities

- `secret-concealment`: which files conceal, what a cover hides, what reveals
  it, and what concealment never touches.

### Modified Capabilities

- `editor`: the paint-order requirement gains the redaction cover's place —
  over the text and every band, under the caret. The requirement's own rule is
  that a band added later takes a stated place rather than being layered where
  it is convenient.

## Impact

- **AbydosKit**: a new `DotenvSecrets` type — `conceals(fileNamed:)` for the
  name shapes (dotenv and `*.dec`), and per-line value ranges (`export` prefixes, quoted values,
  comments) — with fixture tests.
- **AbydosApp**: `CodeView` draws the covers after the text (a new place in
  the stated paint order), tracks the two reveal states (one value by click,
  the file by toggle), and re-conceals when the caret leaves the revealed
  line; a View-menu item and a driver surface.
- **Cost**: the ranges are computed per visible row from the line's text, the
  same shape the search bands already pay; nothing per keystroke beyond the
  row being redrawn anyway.
- Out of scope, named in the design: the diff view, the terminal, and
  content-based secret detection in arbitrary files.
