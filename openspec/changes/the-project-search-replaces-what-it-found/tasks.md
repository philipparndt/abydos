## 1. The engine, in AbydosKit

- [x] 1.1 `TextSearch.replaceAll` takes a filter — which matches to replace —
      and answers how many it kept, so a selection is one span edit like a
      Replace All is; the existing callers pass nothing and are unchanged.
- [x] 1.2 `ProjectReplace.edit(in:question:template:choosing:)` in
      `Sources/AbydosKit/Search`: matches the current text, marks them with
      `SearchChecklist.marks(for:)`, keeps the chosen marks (or all), and
      answers the edit, the count and the marks not found.
- [x] 1.3 `ProjectReplace.Record`: per file the span's range, the text before
      and after, and whether it was open; `undo(applying:)` and
      `redo(applying:)` that check the span still reads what they expect and
      say how many files were skipped.
- [x] 1.4 `ProjectReplaceTests`: chosen marks only, a heading's marks, a
      dirty text with a line inserted above, a match gone since the search,
      two identical lines with one chosen, `$1Id` across three files, a
      template the pattern cannot use, the unmatched text byte-for-byte, and
      a record undone once with one file changed under it.

## 2. The pane

- [x] 2.1 `SearchPane`: the replace row — field, Replace, Replace All — with
      `isReplacing`, `setReplacing`, `focusReplaceField`, and the `⇄` toggle in
      the option row; heights 62 wide and 90 narrow, `applySettings` follows.
- [x] 2.2 The template's validity asked whenever the query, the switches or the
      replacement change; both buttons disabled and `Replacement cannot be
      used` in the status line when it cannot be; Replace disabled with no
      selection, Replace All disabled on an empty or capped list.
- [x] 2.3 `ResultChecklist`: the selection as marks and every showing row as
      marks, both from `ResultRows.marks(under:)`; the pane asks it for the
      chosen set and the list's `markUndo` for the undo entry.
- [x] 2.4 The replacement itself: per file, `document(for:)` through the
      window, the edit through `TextDocument.replace` when open and an atomic
      write when not, inside `StallWatch.mark("project replace")`; a
      `ProjectReplace.Record` registered on the list's undo, whose undo and
      redo apply through the same two paths and report what was skipped.
- [x] 2.5 The status line leads with `N replaced in M files`, `· K not found`,
      then what the re-run finds; the search is run again after a replacement;
      the mode and the replacement survive `setProject`.
- [x] 2.6 *Replace in Project…* in the Edit menu, ⇧⌘R, after *Find in Project…*;
      `MainWindowController.replaceInProject(_:)` makes the pane, seeds from
      the selection when the pane was not up, turns the mode on and focuses the
      field; *Review Branch…* keeps its item and loses its key. ⇧⌘F focuses the
      query and leaves the mode alone.

## 3. Proving it

- [x] 3.1 `--search-steps` gains `replacing`, `replacement:<text>`, `replace`
      and `replace-all`; `status` prints `replacing=` and the last
      replacement's count; the tree's `ls`/`cat` steps read the files back.
- [x] 3.2 Driven on a scratch copy under the scratchpad, built as
      `de.rnd7.abydos.replace` with an unpinned UUID and a throwaway defaults
      domain: two of three selected; a heading folded shut; four done rows
      hidden under Replace All; an open dirty tab with a line typed above the
      matches, then ⌘Z in the tab; a closed file with matches first and last
      line; a capped list; ⌘Z in the list across three closed files and one
      open tab, then once more with one file edited by hand. Recorded in the
      design under a dated heading, with the load beside anything timed.
- [x] 3.3 ␣ and ⌫ in replace mode mark and never replace; Replace never marks:
      driven, and the `search` delta's two scenarios read against it.

## 4. Before finishing

- [x] 4.1 One `##` in the next version's release notes, in the shape of 0.20.6.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate the-project-search-replaces-what-it-found`.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where `search` is what this change
amends and `replace-in-project` is what it adds.
