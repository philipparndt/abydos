## 1. What actually happens today

- [x] 1.1 A driver verb that switches tabs after a find — `--find` then a tab
      selection — because nothing can drive that gesture now and the stale-match
      path was read rather than seen.
- [x] 1.2 Drive it against a scratchpad copy, never a real checkout: two files,
      one searched for a word the other does not have, then switch and step. Say
      what happens — a wrong band, a caret past the end, or a crash. **That
      answer goes in the spec**; the requirement claims a fault and has to be the
      fault there is.
- [x] 1.3 The same with a file shorter than the other's match offsets, which is
      the case `caret = range.upperBound` has no clamp for.

## 2. Find state on the tab

- [x] 2.1 `Tab` gains the find state: showing, query, options, matches, current
      index — beside `codeView` and `document`, which are what the offsets mean.
- [x] 2.2 `EditorViewController` keeps the one `FindBar` view and stops keeping
      `searchMatches` and `currentMatchIndex`.
- [x] 2.3 `showFind`, `closeFind`, `setFindQuery`, `runFind`, `stepMatch` and
      `isFindVisible` read and write the active tab's state.
- [x] 2.4 `activate(index:)` restores it, as one named call that touches nothing
      about responders. The two comments about where the keyboard goes — items
      510 and 523, with their measurements — stay exactly as they are.
- [x] 2.5 A PDF tab is a tab: its query and open-ness are the tab's, its matches
      stay `PdfFileView`'s.
- [x] 2.6 Closing a tab takes its find state with it, because it lives on the
      tab. Assert it rather than assume it.

## 3. Nothing found, and nothing run

- [x] 3.1 `setStatus` takes what to say and whether it is a failure, and colours
      the label and the field together.
- [x] 3.2 `gitConflict` for both, which is the red the field already uses for an
      invalid pattern. No new scheme role — a required one refuses every scheme
      that predates it, and an optional one needs a stated derivation there is no
      other red to write.
- [x] 3.3 An empty query is plain and silent.
- [x] 3.4 A pattern that does not compile says it is incomplete, does not say
      `No results`, does not run a search, and does not clear the matches of the
      last query that did.
- [x] 3.5 The comment at `notifyQueryChanged` becomes true, and says that the
      label is now the half that distinguishes the two.

## 4. Tests as claims

- [x] 4.1 `findBelongsToTheTabItWasOpenedIn`,
      `theMatchesDoNotOutliveTheTabThatFoundThem`,
      `aPatternThatDidNotCompileDoesNotSayNoResults`,
      `anEmptyQuerySaysNothing`.
- [x] 4.2 Where the state is unreachable from the suite — it is on a view
      controller in the app target — the claim is checked by driving, and the
      report says what it saw rather than that it looked.
- [x] 4.3 No wall-clock assertion. If one is wanted, `MachineLoad.said` prints
      the load beside it and `Stopwatch.maySay` decides whether a bound may be
      asserted at all.

## 5. Watched

- [x] 5.1 Two tabs, find open in one, photographed both ways round.
- [x] 5.2 A query with no results, photographed: both the text and the label red.
- [x] 5.3 An incomplete pattern, photographed beside it, saying something else.
- [x] 5.4 Every scheme in the repository, since the red is the scheme's: the same
      capture under each, so a red that vanishes into a background is seen now
      rather than reported later.

## 6. Finish

- [x] 6.1 `make test` and `make warnings`, both clean, and their exit codes mean
      what they say.
- [x] 6.2 Write down what was ruled out, including the scheme role and why
      `SchemeRole.optional` does not rescue it.
