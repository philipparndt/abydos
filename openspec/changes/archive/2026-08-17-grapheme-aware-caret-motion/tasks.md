## 1. Decide the scope before writing anything

- [x] 1.1 Probe ⌫ and ⌦ over a decomposed accent with `--emacs-nav` and a probe, the
      way the motion was probed. This decides whether this is one change or two.
- [x] 1.2 Read every caller of `Rope.alignToBoundary` and say which of them wants a
      grapheme and which wants a byte. Record the list here.

## 2. The boundary itself

- [x] 2.1 Choose between Swift's `Character` view over a window of the rope and
      `CFStringGetRangeOfComposedCharactersAtIndex` in UTF-16. Measure both on a
      large file, since this runs on every keystroke, and say in the comment which
      was measured and what it cost.
- [x] 2.2 Implement the grapheme step in `moveHorizontally`, leaving the byte
      alignment where it is — unless 1.2 said otherwise, in which case say why.

## 3. The keys

- [x] 3.1 ←, →, ⌃B and ⌃F each step one grapheme, with and without Shift.
- [x] 3.2 ⌫ and ⌦ remove one grapheme, if 1.1 put them in scope.
- [x] 3.3 ⌃O still cancels over a lone `\r` — the case most likely to be broken by
      this fix, because it works today for exactly the reason being changed.

## 4. Watched, not only tested

- [x] 4.1 `--emacs-nav` on a line with a decomposed `é`, showing 13 → 15.
- [x] 4.2 The same on a ZWJ sequence and a skin-tone modifier.
- [x] 4.3 An emoji is still one step — the existing scenario, unbroken.

## 5. Finish

- [x] 5.1 `make test` and `make warnings` both clean.
- [x] 5.2 Write down what was ruled out on the way — including that calling this a
      spec error and rewriting the sentence was considered and refused, because a
      caret that can land inside a character is a bug rather than a decision.
- [x] 5.3 `.abydos/backlog/spec/editor.md` — the sentence about a combining mark
      becomes true rather than changes. Add the decomposed-accent scenario beside the
      emoji one, since the emoji scenario is what let this hide.

## 6. What the probing settled

- [x] 6.1 **Deletion was in scope** (1.1). `deleteBackward` had the same fault
      under a comment claiming otherwise — "delete a whole composed character",
      stepping by UTF-8 sequence — and `deleteForward` had a *third* copy of the
      byte walk, forwards over continuation bytes. All four keys now ask the rope
      the one question.
- [x] 6.2 **Both callers of `alignToBoundary` wanted graphemes** (1.2), and there
      were only two. It is kept as the byte-level primitive it always was, with a
      comment saying what it is for, rather than being widened underneath callers
      that might not want it.
- [x] 6.3 **The argument expected to choose the boundary API was false** (2.1).
      `CFStringGetRangeOfComposedCharactersAtIndex` was supposed to split a ZWJ
      family; on macOS 27 it does not. What separates them is `\r\n`, where it
      answers 1 and would let → rest between the two halves — the same fault one
      character along. Cost did not decide it: 0.12 µs against 0.21 µs, both
      nothing beside the 35 µs the rope window costs.
