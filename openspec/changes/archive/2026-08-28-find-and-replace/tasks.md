## 1. The replacement, in the kit where it can be tested

- [x] 1.1 `TextSearch` gains what one match becomes: a template applied to a
      match under given options — literal when the regular-expression switch is
      off, `NSRegularExpression`'s template when it is on, with `$0` and `$1`
      meaning what the engine already means by them.
- [x] 1.2 `TextSearch` gains the whole of a Replace All: from text, query,
      options and template, the single span from the first match's start to the
      last match's end and the new text of that span. One value, so the editor
      makes one edit and the undo history one entry.
- [x] 1.3 A template that names a capture the pattern does not have is refused,
      as `isValid` refuses a pattern that will not compile — same shape, same
      place in the bar.
- [x] 1.4 `Tests/AbydosKitTests/ReplaceTests.swift`: a literal `$1` stays `$1`
      with the switch off; `(\w+)_id` → `$1Id` turns `user_id` into `userId`;
      replacing every match leaves the text between them byte-for-byte; a
      template naming `$7` against two captures is refused; replacing in an empty
      file and with no matches changes nothing. Names are sentences.

## 2. The matches follow the text

- [x] 2.1 `EditorViewController` adjusts the tab's matches on
      `onTextReplaced` — the edit in UTF-16, which is the unit a match is in;
      `onLinesChanged` carries lines and cannot say where a match went. Fanned
      out through `CodeView`, whose own `onTextReplaced` the snippet session
      already holds: a match before the edit is kept, one overlapping it is
      dropped, one after it is shifted by the edit's delta, and the current index
      is kept pointing at the same match where it survives.
- [x] 2.2 The same hook schedules the search again on the debounce `scheduleFind`
      already uses, so the adjustment is replaced by the true answer 120 ms later.
      Not `TextDocument.onTextChanged` — that is a single closure the PlantUML,
      Mermaid and draw.io panes assign, and taking it would stop a `.puml` file
      redrawing. The re-run keeps the current match rather than recomputing it
      from the caret, which would step forward one on every edit.
- [x] 2.3 Only for a tab with find showing: a file with no find bar open pays
      nothing for this.
- [x] 2.4 Reproduce the capture in the proposal by hand first — search a file for
      a path, edit the path off most of the lines — and keep it as the thing to
      check at the end.

## 3. The bar's replace half

- [x] 3.1 `FindBar` gains a mode and a second row: the replacement field, Replace
      and Replace All, under the existing row and hidden in find mode. The height
      the bar reports goes up with it, through `findBarHeight`.
- [x] 3.2 The row is offered only where there is something to edit — a tab with a
      document and a code view — and not for a PDF.
- [x] 3.3 `Tab.FindState` gains `replacement` and `isReplacing`, and
      `restoreFind(for:)` puts both back with the query, so a tab comes back as it
      was left.
- [x] 3.4 Return in the replacement field replaces the current match, ⇧Return
      replaces and steps backwards, ⎋ closes the bar — the same conventions the
      query field already keeps.

## 4. Replacing

- [x] 4.1 Replace the current match through `TextDocument.replace`, then make the
      next match current. The tab is marked dirty and one ⌘Z takes it back,
      because it is an ordinary edit.
- [x] 4.2 Replace All applies the single span from 1.2 as one
      `TextDocument.replace`. Check the undo history holds one entry afterwards,
      not one per match.
- [x] 4.3 After either, the matches are re-run by the hook from section 2 rather
      than by anything replace does for itself. Replace is an edit; it should need
      no special case.

## 5. The shortcut

- [x] 5.1 ⌘R in the Edit menu, beside Find… and Find Next: opens the bar in
      replace mode, or switches an open one, and puts the keyboard in the
      replacement field. ⌘R is unbound today — Run is ⌃R, Go Run ⌃⌘R, Review
      Branch ⇧⌘R — so nothing is taken from anything.
- [x] 5.2 ⌘F leaves the mode alone: it opens the bar or focuses the query and
      does not collapse a replace row somebody has typed into.
- [x] 5.3 A driven-run verb that opens the bar in replace mode, types a
      replacement, presses Replace All and prints what the file became, so the
      whole path can be checked without a person.

## 6. Finishing

- [x] 6.1 Drive it against a copy under the scratchpad, with a throwaway bundle
      id and an unpinned UUID, and a defaults domain of its own. Never
      `make install`.
- [x] 6.2 `make test` and `make warnings`, both clean, and their exit codes read
      rather than their output skimmed.

## What this makes untrue

`openspec/specs/editor/spec.md` describes find as a thing that happens to a tab
and is remembered by it, and says nothing about what an edit does to what was
found — which is why nothing did anything. The delta in `specs/editor/spec.md`
adds that rule. Nothing already written there stops being true: the current match
is still the loudest thing on the page, find still belongs to the tab that
searched, and a search that found nothing still says so in red.

There is no `.abydos/backlog/spec` file to name. That backlog is gone, and
`openspec/specs` is the account it kept.
