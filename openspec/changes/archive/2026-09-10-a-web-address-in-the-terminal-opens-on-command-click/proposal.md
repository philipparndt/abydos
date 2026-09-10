## Why

Feedback relayed by the maintainer, 2026-09-10: *"Command + Hover identifiziert
Hyperlinks (Kennzeichnung durch Underline) und öffnet Browser mit dem Link.
Wäre auch nice"* — ⌘ held over a link should underline it, and a click then
should open it in the browser. That is Terminal.app's and iTerm2's convention,
and the one a Mac user's hands already know.

Reading finds the terminal halfway there, and halfway in a different direction.
A hyperlink a program *marks* — OSC 8, which `ls --hyperlink`, `gh` and every
modern CLI emit — is known to the emulator, the pointer over one becomes a hand
(`TerminalView+Mouse.swift`, `updateHoveredLink`), a bare click opens it
(`mouseDown`, before selection is considered), and the hovered one is underlined
by the GPU renderer (`TerminalMetalRenderer.swift:631`) but **not by the
CoreGraphics one**, which draws no underline for it at all. Three things are
missing or wrong against the convention asked for:

- **A web address that is merely printed is not a link.** `https://…` in a
  build log, a stack trace, a `git push` result or an agent's answer is plain
  text here. Every terminal on this platform detects those, and they are most
  of what anybody wants to open.
- **A bare click opens a marked link**, where the convention is ⌘-click. A bare
  click over text is how a selection begins, and a click that opened a browser
  instead is a trap: the one place selecting text is punished.
- **The underline appears on hover, in one renderer.** The convention is to
  underline while ⌘ is held, so that the pointer resting on a page never draws
  anything, and to do it in both renderers.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-10.

## What Changes

- **Web addresses are found in the text**, per visible line, as a run matching
  `https?://` (and `mailto:`) up to whitespace or a closing bracket — with the
  usual trailing punctuation left out, so a URL at the end of a sentence does
  not carry the full stop. Found for the rows on screen and only when ⌘ is
  down or a click asks, never per frame for the whole scrollback.
- **⌘ held underlines the link under the pointer**, marked or found, in both
  renderers, and makes the pointer a hand. Without ⌘ the pointer over a link is
  an I-beam and nothing is drawn, as over any other text.
- **⌘-click opens it**, through `NSWorkspace`, and the click does not start a
  selection. A bare click over a link selects text as it does everywhere else.
- **A marked link keeps its target** when it is also a web address in the
  text: the OSC 8 target wins, because the program said what it meant.

## Capabilities

### Modified Capabilities

- `terminal`: what a link in a pane is, when it is shown as one, and what
  opens it.

## Impact

- **AbydosKit**: a finder for web addresses in a line of cells, without a
  window, so the rule for "where does the address end" is a test.
- **AbydosApp**: `TerminalView+Mouse.swift`, the click and the hover;
  `TerminalView+Drawing.swift` and `TerminalMetalRenderer.swift`, the underline
  under ⌘; a `flagsChanged` so the underline follows the key and not only the
  pointer.
- **Driving**: a step that puts ⌘ and the pointer on a printed address and says
  what is underlined and what a click would open.
