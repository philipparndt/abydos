# 504. A decomposed accent is two steps of ⌃F and the spec says one

`spec/editor.md`, under "⌃B and ⌃F move the caret a character, and so do ←
and →":

> A character is a composed character, so an emoji or a letter with a
> combining mark is one step and not two.

Half of that is true. The alignment the four horizontal keys go through is
`Rope.alignToBoundary`, and all it does is walk back over UTF-8 **continuation
bytes**:

    public func alignToBoundary(_ offset: Int) -> Int {
        var o = max(0, min(offset, byteCount))
        while o > 0 && o < byteCount {
            let b = bytes(in: o..<(o + 1))
            guard let first = b.first, Rope.isContinuation(first) else { break }
            o -= 1
        }
        return o
    }

That is **code-point** alignment, not grapheme alignment. An emoji is a single
code point, so `🙂` is one step and 0497's scenario is right. `e` + U+0301 is
two code points, and each of them starts with a byte that is not a
continuation byte, so the caret stops between the letter and its accent —
where no caret should ever be, and where the next keystroke edits half a
character. The same goes for a flag, a skin-tone sequence, or anything else
joined with a ZWJ.

Watched with `--emacs-nav` and a probe that was taken out again, on a line
whose second character is a decomposed `é` starting at offset 13:

    EMACS: PROBE mark  caret=13 selection=13..<13 “”
    EMACS: ⌃F          caret=14 selection=14..<14 “”

13 → 14, not 13 → 15.

It is ←, →, ⌃B and ⌃F together, and ⇧ with any of them — one function,
`moveHorizontally`, which every one of them reaches. Nothing here is new: the
alignment has been code-point alignment since it was written. What is new is
knowing it, and that the spec claims otherwise.

**Found while doing [0503](../completed/), which needed to know what
`moveHorizontally` aligns to in order to say whether ⌃O's two halves cancel
after a lone `\r`.** They do, and for this reason: `\r\n` is one grapheme and
two code points, so the step back does not swallow the pair. The bug and the
thing that made ⌃O correct are the same fact.

## Worth deciding

- **Where the grapheme boundary comes from.** `Rope` has no notion of one
  today. Swift's `String` does — `index(after:)` on a `Character` view — but
  the rope is bytes and asking it for a `String` around the caret to step one
  character is the same shape as `wordTarget`'s window, which reads a few
  hundred bytes either side rather than the whole file. `CFStringGetRangeOfComposedCharactersAtIndex`
  is the other candidate and works in UTF-16, which is what the caret is.
- **Whether `alignToBoundary` changes or only its caller.** It is used for
  more than the caret; a wider definition of a boundary may be wrong for some
  of those. The narrower change is a grapheme step in `moveHorizontally` and
  the byte alignment left where it is.
- **Deleting is the same question.** ⌫ and ⌦ over a decomposed accent very
  likely leave the base letter behind or the mark orphaned. Worth one probe
  before deciding the scope, and worth doing in one item with the motion
  rather than as a second one afterwards.

## Ruled out

- **Calling it a spec error and fixing the sentence.** The spec says what the
  project does, so an untrue sentence could be corrected by rewriting it — but
  a caret that can land inside a character is a bug rather than a decision,
  and the sentence describes what the editor is supposed to do. Fix the
  editor and the sentence becomes true.

## Steps

- [ ] Probe ⌫ and ⌦ over a decomposed accent, to know whether this is one
      item or two
- [ ] The four horizontal keys step over a whole grapheme
- [ ] Watched with `--emacs-nav`, a decomposed accent and a ZWJ sequence
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what the project now does — the sentence about a
      combining mark is already there and will become true rather than change
