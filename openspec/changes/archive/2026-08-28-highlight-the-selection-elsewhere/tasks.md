## 1. What counts, and where it is, in the kit

- [x] 1.1 Add `Sources/AbydosKit/Search/SelectionOccurrences.swift`: whether a
      selection is one worth answering — two characters or more, no line break,
      not only whitespace — and where its text appears in a document, as UTF-16
      ranges, case-sensitive and literal, bounded by `TextSearch.matchLimit`.
      Ranges rather than `SearchMatch`: the bands need offsets, and building a
      line's text for each of five thousand hits is work nothing reads.
- [x] 1.2 `Tests/AbydosKitTests/SelectionOccurrenceTests.swift`: `count` finds the
      `count` inside `accountId`; `Count` does not find `count`; one character,
      a selection with a newline in it and a run of spaces each qualify for
      nothing; a selection appearing nowhere else gives no ranges; the ranges
      come back in file order and stop at the cap. Names are sentences.

## 2. A colour that no scheme has to know about

- [x] 2.1 Add the `SchemeRole` for it, in the `optional` set, with a derivation in
      `Scheme.readApp` from colours a scheme already sets — quieter than
      `searchMatchBackground`, since a find match is an answer somebody asked for
      and this is not.
- [x] 2.2 The fallback in `SchemeLibrary` states it outright, the way it states
      every other colour it draws with rather than deriving.
- [x] 2.3 Read it into `Theme` beside `searchMatchBackground`, and add it to
      `ThemeSwap` so it changes with the rest when a scheme is swapped.
- [x] 2.4 Check the five scheme files still load untouched — `abydos`, `blue`,
      `dracula`, `gray`, `editor` — which is the claim the `optional` set exists
      to make.

## 3. The bands

- [x] 3.1 `CodeView` holds the occurrence ranges beside `searchMatches`, and
      `searchHighlights(docLine:segment:rect:)` places them the way it already
      places a match: per visual row, per wrap segment.
- [x] 3.2 Painted at the non-current match's depth — over the line background,
      under the selection — and never over the selection itself.
- [x] 3.3 Nothing is drawn or looked for while the view holds find matches.
- [x] 3.4 The selection's own range is not banded.

## 4. When to look

- [x] 4.1 The scan is scheduled from `reportCaretPosition`, the funnel every path
      that moves the caret or extends a selection already goes through, drag
      included. Say in a comment that the function's name is about the caret and
      that this makes it also mean "the selection may have changed".
- [x] 4.2 Debounced, so a drag across a paragraph is one scan at the end.
- [x] 4.3 The bands are dropped the instant the selection changes, before the new
      answer is known: the selection is the query, so nothing survives it
      changing.
- [x] 4.4 The same on an edit, through the `onTextReplaced` fan-out the find
      matches already use — an agent rewriting the file under a standing
      selection must not leave a band at an offset the old text had.

## 5. Driving it, and finishing

- [x] 5.1 A driven-run verb that selects a range and prints what is banded, the
      way `--select-lines` selects and the find report prints offsets. It is the
      only way to check any of section 3 without a person, since `Tests/` covers
      `AbydosKit` and nothing in `AbydosApp`.
- [x] 5.2 Drive it against a copy under the scratchpad, with a throwaway bundle
      id and an unpinned UUID, and a defaults domain of its own: select a name
      that appears three times and read the three ranges back; select one
      character and read none; open find and check the occurrence bands go.
      Never `make install`.
- [x] 5.3 A screenshot of the bands beside a selection, since the claim this
      change makes is about what something looks like and the colour derivation
      is the part a report cannot check.
- [x] 5.4 `make test` and `make warnings`, both clean, and their exit codes read
      rather than their output skimmed. `CodeView` is on the file-size list; if
      it grows past its recorded length, raise the number in
      `Scripts/file-size-allowed.txt` in the same commit, which is what that
      list's own rule asks for.

## What this makes untrue

`openspec/specs/editor/spec.md` describes the find highlights and the selection
and the order they are painted in, and says nothing about a third kind of band —
which is right, because there was not one. The delta in `specs/editor/spec.md`
adds the rule that order was already keeping, so that the next band to arrive
inherits it rather than rediscovering item 0536.

Nothing already written there stops being true. The current find match is still
the loudest thing on the page, and it is drawn over the selection for the reason
it always was.

There is no `.abydos/backlog/spec` file to name. That backlog is gone, and
`openspec/specs` is the account it kept.
