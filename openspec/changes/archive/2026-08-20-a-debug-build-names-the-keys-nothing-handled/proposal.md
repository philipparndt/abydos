## Why

A key that moves the caret without Shift and does nothing with it has been the
same bug three times — 0494 twice and 0495 once — and each time the diagnosis was
somebody reading `CodeView.doCommand`'s switch and noticing which name was
absent. The editor could say it instead.

`doCommand` ends in `default: break`, and staying quiet there is right: AppKit
sends `noop:` and a good deal else a text view has no business printing about.
But a *motion* arriving there is a key somebody pressed that did nothing.

## What Changes

- **In a debug build, the first unhandled `move…` or `select…` selector names
  itself**, once per selector, and never again — not in a release build, and not
  for anything outside those two families.
- **The ceiling is a countable few, counted rather than guessed.** Against the
  macOS 27.0 SDK on 2026-08-16, `NSResponder.h` declared 43 methods beginning
  `move` or `select` and `doCommand` handled 29 — fourteen possible lines:

      moveBackward                              moveToBeginningOfParagraph
      moveBackwardAndModifySelection            moveToBeginningOfParagraphAndModifySelection
      moveForward                               moveToEndOfParagraph
      moveForwardAndModifySelection             moveToEndOfParagraphAndModifySelection
      moveParagraphBackwardAndModifySelection   selectLine
      moveParagraphForwardAndModifySelection    selectParagraph
                                                selectToMark
                                                selectWord

  **Counted again on 2026-08-20, when this was built: 43 declared, 39 handled,
  four left** — `selectLine`, `selectParagraph`, `selectToMark` and `selectWord`.
  Ten of the fourteen were taken in the four days between, which is the shape of
  thing this exists to keep visible. The count reproduces with a `grep` over that
  header, and a test now does it against the SDK the build is using: it is the
  size of a family AppKit fixes at compile time, not a function of how long the
  app runs.
- **The drivers press keys**, and that is what makes this worth more than it
  sounds. `--vertical-nav` and `--word-nav` sweep a corner of the keyboard
  already; a debug run of either would print the unhandled selectors beside its
  own report. 0494's session pressed ⇧⇞, ⇧⇟, ⌘⇧↑ and ⌘⇧↓ through the driver, so
  all four would have named themselves in one run.
- **Not proposed: logging every unhandled selector.** That is what the existing
  comment refuses, and rightly: `noop:` alone would drown it, and that set has no
  ceiling worth quoting.
- **Not a detector.** Nothing prints until a key is pressed. It turns "this key
  does nothing, why?" into "this key does nothing, and here is the selector
  nobody handled".

## Capabilities

### New Capabilities

<!-- None. -->

### Modified Capabilities

<!-- None. This is what a debug build says about itself, not what the editor
     does. Whether it earns a requirement is decided in the work; the item says
     it may well not. -->

## Impact

- `Sources/AbydosApp/Editor/CodeView.swift` — `doCommand`'s `default:` branch.
- Wherever this project already logs from a debug build, rather than a bare
  `print`.
- From `.abydos/backlog` item 0496.
