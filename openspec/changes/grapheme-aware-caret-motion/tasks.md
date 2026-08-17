## 1. Decide the scope before writing anything

- [ ] 1.1 Probe ⌫ and ⌦ over a decomposed accent with `--emacs-nav` and a probe, the
      way the motion was probed. This decides whether this is one change or two.
- [ ] 1.2 Read every caller of `Rope.alignToBoundary` and say which of them wants a
      grapheme and which wants a byte. Record the list here.

## 2. The boundary itself

- [ ] 2.1 Choose between Swift's `Character` view over a window of the rope and
      `CFStringGetRangeOfComposedCharactersAtIndex` in UTF-16. Measure both on a
      large file, since this runs on every keystroke, and say in the comment which
      was measured and what it cost.
- [ ] 2.2 Implement the grapheme step in `moveHorizontally`, leaving the byte
      alignment where it is — unless 1.2 said otherwise, in which case say why.

## 3. The keys

- [ ] 3.1 ←, →, ⌃B and ⌃F each step one grapheme, with and without Shift.
- [ ] 3.2 ⌫ and ⌦ remove one grapheme, if 1.1 put them in scope.
- [ ] 3.3 ⌃O still cancels over a lone `\r` — the case most likely to be broken by
      this fix, because it works today for exactly the reason being changed.

## 4. Watched, not only tested

- [ ] 4.1 `--emacs-nav` on a line with a decomposed `é`, showing 13 → 15.
- [ ] 4.2 The same on a ZWJ sequence and a skin-tone modifier.
- [ ] 4.3 An emoji is still one step — the existing scenario, unbroken.

## 5. Finish

- [ ] 5.1 `make test` and `make warnings` both clean.
- [ ] 5.2 Write down what was ruled out on the way — including that calling this a
      spec error and rewriting the sentence was considered and refused, because a
      caret that can land inside a character is a bug rather than a decision.
- [ ] 5.3 `.abydos/backlog/spec/editor.md` — the sentence about a combining mark
      becomes true rather than changes. Add the decomposed-accent scenario beside the
      emoji one, since the emoji scenario is what let this hide.
