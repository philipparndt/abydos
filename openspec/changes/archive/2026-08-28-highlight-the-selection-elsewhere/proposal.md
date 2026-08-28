# Highlight the selection elsewhere

## Why

Select a name in a file and the editor says nothing about where else it is. The
question "where else is this" is asked constantly while reading code — before a
rename, while working out what a variable is for, while checking whether a
string literal is written twice — and the app has two answers for it, both of
which cost more than the question is worth.

⌘F answers it and takes over: the bar opens, the keyboard goes into it, the
query has to be typed or the selection re-seeded, and getting back to the code
means pressing ⎋, which throws the answer away. Find in Project answers a
broader question in a pane at the bottom of the window, and reading a list of
rows to learn "twice more, both on screen" is not reading.

Every part needed for the cheap answer is already here. `TextSearch` finds
literal occurrences and returns UTF-16 ranges. `CodeView` already draws bands
from ranges, per visual row, wrap-aware — `searchHighlights(docLine:segment:rect:)`
is the function, and it already paints at two depths so that the current find
match survives being covered by the selection. What is missing is a scan that
starts when a selection is made rather than when a query is typed.

## What Changes

- **A selection of two or more characters on one line highlights every other
  place the same characters appear**, without opening anything. The bands are
  the find bands' quieter relative: this is information nobody asked for, and it
  must not look like the answer to a question somebody did ask.
- The matching is literal and **case-sensitive**, which is what a selection is —
  `Count` selected does not light `count`. Partial words match, because a
  selection is a run of characters and not a symbol: selecting `count` lights the
  `count` inside `accountId`.
- **A selection of one character lights nothing**, and neither does one that
  spans lines or holds nothing but whitespace. One character would band every
  `e` on the page, and a selected indent would band every indent in the file.
- **Find wins while it is showing matches.** Two kinds of band on one page,
  meaning two different things, is worse than one kind meaning one thing — and
  the one somebody asked for is find's.
- The bands go away the moment the selection changes and the moment the text
  under them does. Stale bands over text that no longer matches is the fault
  `find-and-replace` was written to fix; this must not reintroduce it by another
  door.

## Capabilities

### New Capabilities
- `selection-occurrences`: highlighting the other places a selection's own text
  appears in the file being read — what counts as a selection worth answering,
  what is matched, what is drawn, and when the answer is taken away.

### Modified Capabilities
- `editor`: a third kind of band arrives on a row that already draws the
  selection, the find matches and the current find match at three different
  depths. The rule that ordering encodes — the current match is the loudest
  thing on the page — is unchanged and is now something the new band must not
  break.

## Impact

- New `Sources/AbydosKit/Search/SelectionOccurrences.swift`: whether a selection
  is one worth answering, and where its text appears. A value with a test on it,
  which is the only part of this that `Tests/` can reach.
- `CodeView` gains the ranges and draws them at the depth the find matches'
  non-current band already uses — under the selection, over the line
  background. `searchHighlights` is the function that already does this per
  visual row and per wrap segment; nothing new is needed to place a band.
- The scan hangs off `reportCaretPosition`, the funnel every path that moves the
  caret or extends a selection already goes through, and is debounced the way
  find already debounces: a drag across a paragraph is one scan and not one per
  mouse-moved.
- One new `SchemeRole`, in the `optional` set with a stated derivation. That set
  and the derivations exist for exactly this — a colour that arrives after people
  already keep scheme files in dotfiles repositories — so **no scheme file needs
  editing and none is refused for lacking it**.
- Nothing in the find path changes. The bar, its matches, its debounce and its
  precedence are as they are.
