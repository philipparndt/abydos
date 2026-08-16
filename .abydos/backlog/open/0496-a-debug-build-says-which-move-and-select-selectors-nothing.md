# 496. A debug build says which move: and select: selectors nothing handled

`CodeView.doCommand` ends in a `default: break` whose comment says staying
quiet is right, and it is right — AppKit sends `noop:` and a good deal else
that a text view has no business printing about. But a *motion* that arrives
there is a key that the editor moves the caret for without Shift and does
nothing at all for with it, and that has now been the same bug three times:

- **0494**, ⇧⇞ and ⇧⇟ — `pageUpAndModifySelection:` and
  `pageDownAndModifySelection:`, found by accident while watching ⇧↓.
- **0494 again**, ⌘⇧↑ and ⌘⇧↓, spotted in the same session and left alone.
- **0495**, the same two, fixed.

Each time the symptom was identical and useless: a key that does nothing. Each
time the diagnosis was somebody reading the switch and noticing which name was
absent. In a debug build the editor could say it instead — the first time an
unhandled selector matching `move…` or `select…` comes through `default:`, log
its name once, and never again for that selector or in a release build.

## What it would actually cost, in lines printed

Counted rather than guessed, against the macOS 27.0 SDK on 2026-08-16.
`NSResponder.h` declares **43** methods whose names begin `move` or `select`.
`doCommand` handles **29** of them. So the log has a hard ceiling of **14
lines** — for the whole life of a debug build, one line each, and only for a
key somebody actually pressed:

    moveBackward                                  moveToBeginningOfParagraph
    moveBackwardAndModifySelection                moveToBeginningOfParagraphAndModifySelection
    moveForward                                   moveToEndOfParagraph
    moveForwardAndModifySelection                 moveToEndOfParagraphAndModifySelection
    moveParagraphBackwardAndModifySelection       selectLine
    moveParagraphForwardAndModifySelection        selectParagraph
                                                  selectToMark
                                                  selectWord

That is the whole answer to "how noisy is it". The ceiling is the size of a
family AppKit fixes at compile time, not a function of how long the app runs or
how much is typed, which is what makes it different from logging `default:`
whole. Reproduce the count with:

    H=$(xcrun --sdk macosx --show-sdk-path)/System/Library/Frameworks/AppKit.framework/Headers/NSResponder.h
    grep -o '\- *(void)\(move\|select\)[a-zA-Z]*:' "$H" | sed 's/.*)//;s/:$//' | sort -u

## What it would and would not have caught

Worth being exact, because the tempting claim is too strong. **It does not find
a bug nobody triggers.** Nothing prints until the key is pressed. What it does
is turn "this key does nothing, why?" into "this key does nothing, and here is
the selector that nobody handled" — the reading-the-switch step, which took
real time on 0494, done by the program.

The reason that is worth more than it sounds: **the drivers press keys.**
`--vertical-nav` and `--word-nav` already sweep a corner of the keyboard on
purpose, and a debug run of one of them would print the unhandled selectors
alongside its own report. That is the difference between a diagnosis
accelerator and a detector, and it is free — the driver runs are already part
of doing an editor item.

On the three above: 0494's session pressed ⇧⇞, ⇧⇟, ⌘⇧↑ and ⌘⇧↓ through the
driver, so all four selectors would have printed in that one run, before anyone
went looking at the switch.

## Ruled out

- **Logging every unhandled selector.** That is what the existing comment is
  refusing and it is right to. `noop:` alone would drown it, and unlike the
  `move`/`select` family the set has no ceiling worth quoting.
- **Doing it inside 0495.** 0495 is two selectors and this is a change to how
  the editor reports about itself; the two want deciding separately, which is
  why this is a file and not a paragraph.

## Steps

- [ ] Decide where it logs — the project's existing debug logging, if there is
      one, rather than a bare `print`
- [ ] `default:` names an unhandled `move…`/`select…` selector once, in debug
      builds only
- [ ] It says nothing at all in a release build, checked rather than assumed
- [ ] Confirmed against a real key: press ⌃B in a debug build and see
      `moveForward:`/`moveBackward:` named
- [ ] `make test` and `make warnings` both clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` — only if this is behaviour worth a requirement, and it
      may well not be; say which, here

## Found on the way, in 0495

The same audit turned up that **⌃B and ⌃F do nothing** while ⌃P and ⌃N work:
the latter arrive as `moveUp:`/`moveDown:` and are handled, the former as
`moveBackward:`/`moveForward:` and are not. Half-implemented emacs bindings,
nobody has asked for them, not part of this item — but it is one of the 14
lines above, and it is the kind of thing this change exists to surface.
