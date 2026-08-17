## Context

The whole of the current alignment:

    public func alignToBoundary(_ offset: Int) -> Int {
        var o = max(0, min(offset, byteCount))
        while o > 0 && o < byteCount {
            let b = bytes(in: o..<(o + 1))
            guard let first = b.first, Rope.isContinuation(first) else { break }
            o -= 1
        }
        return o
    }

It walks back to the start of a UTF-8 sequence. That is exactly right for "do not
land in the middle of an encoded code point" and says nothing about graphemes.

`Rope` has no notion of a grapheme today, and the rope is bytes.

## Goals / Non-Goals

**Goals:**

- No horizontal keystroke can leave the caret inside a character a reader would
  point at.
- One answer to "where is the next character boundary", not two that agree today.
- The spec sentence becomes true without being rewritten.

**Non-Goals:**

- Word motion. `wordTarget` has its own window and its own definition.
- Bidirectional layout. The requirement already records that ⌃F and → agree only
  because the editor lays text out logically, and that is not changing here.
- Rendering. This is where the caret comes to rest, not how the line is drawn.

## Decisions

**Where the grapheme boundary comes from.** Two candidates, and the choice wants
making with a measurement rather than a preference:

- Swift's `String` — `index(after:)` on the `Character` view. The rope is bytes, so
  this means asking it for a `String` around the caret. That is the same shape as
  `wordTarget`'s window, which reads a few hundred bytes either side rather than the
  whole file, so there is a precedent in the tree for the cost.
- `CFStringGetRangeOfComposedCharactersAtIndex`, which works in UTF-16 — which is
  what the caret is. Fewer conversions, a C API, and it answers the exact question.

**Whether `alignToBoundary` changes or only its caller.** The narrower change is a
grapheme step in `moveHorizontally` with the byte alignment left where it is. That
is preferred unless reading the other callers shows they all want graphemes too:
`alignToBoundary` is used for more than the caret, and widening what a boundary
means could be wrong for some of those — a byte-oriented caller that suddenly skips
a whole ZWJ sequence would be a new bug of the same family, introduced by the fix.

**Cost is a constraint, because this is per keystroke.** Whatever is chosen runs on
every ←. A window around the caret is affordable; converting the document is not.
Say in a comment which was measured.

**Deletion is in scope until the probe says otherwise.** ⌫ and ⌦ almost certainly
share the fault. Doing them in a second item afterwards means deciding the same
question twice and risks the two disagreeing, which is the failure this change is
about in the first place.

## Risks / Trade-offs

- **Two answers to "where is this offset"** → The whole point of preferring reuse
  over a second implementation. Whatever is chosen, one test should hold the motion
  and the deletion to the same boundary, so they cannot drift apart later.
- **A per-keystroke cost that only shows on a large file** → Mitigated by windowing,
  as `wordTarget` already does, and by saying in the comment what it costs.
- **`\r\n` regressing.** It is one grapheme and two code points. Today the step back
  does not swallow the pair, and 0503's ⌃O is correct *because of that*. A grapheme
  step will treat `\r\n` as one unit, which may be right for the caret and wrong for
  ⌃O — check ⌃O explicitly rather than trusting its tests to notice.

## Open Questions

- Does a grapheme step over `\r\n` break ⌃O's two halves cancelling? This is the one
  place where the fix could plausibly break something that works today.
- Is the caret the only `alignToBoundary` caller that wants graphemes? Reading them
  decides whether the change is one function or two.
