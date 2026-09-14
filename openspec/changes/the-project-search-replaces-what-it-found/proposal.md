## Why

The maintainer, 2026-09-14: *"the global find should also support replace"*.

The project search (⇧⌘F) finds and cannot change. Its list is a checklist —
rows are opened, decided on and ticked off — and the deciding, when the answer
is "this one changes", is done by hand: open the row, ⌘R, type the replacement
a second time, Replace, back to the list, next row. Across twenty-seven files
that is twenty-seven find bars with the same two strings typed into each, and
the one thing the list knows — which rows somebody has looked at and which are
still to do — plays no part in it.

The find bar learnt to replace in `replace-in-file`, and everything that made
that safe is already in `AbydosKit`: `TextSearch.replaceAll` makes one edit of
every match, `TextSearch.isValid(template:)` refuses a `$7` against two capture
groups before Foundation can turn it into a silent deletion, and a literal
search takes a literal replacement. None of it is reachable from the pane that
has the whole project's matches in front of it.

There is no originating `.abydos/backlog` item: that backlog is gone, and this
comes from the report above.

## What Changes

- **A replace half on the search pane**, shown while the pane is in replace
  mode and hidden while it is not: a field for what the matches should become,
  a **Replace** for the rows that are selected and a **Replace All** for every
  row the list is showing. The `Aa`, `W` and `.*` switches say what the
  replacement means, exactly as they do in the find bar — literal with `.*`
  off, a `$0`/`$1` template with it on — and a template the pattern cannot use
  is refused in the status line, with nothing written.
- **⇧⌘R opens it**, *Replace in Project…* in the Edit menu, seeded from the
  selection the way ⇧⌘F seeds a search, and switches an open pane to replace
  with the keyboard in the replacement field. ⇧⌘F does not take replace mode
  away. ⌘F and ⌘R in the file, ⇧⌘F and ⇧⌘R in the project. ⇧⌘R was *Review
  Branch…* in the Agent menu, which is barely used (the maintainer,
  2026-09-14); it keeps its menu item and loses its key.
- **Replace acts on rows, not on a current match.** The list's analogue of
  the find bar's "current" is its selection: a selected match is replaced, a
  selected file heading takes every match in that file with it, and Replace
  All takes every row showing. Rows the `✓` toggle is hiding are rows somebody
  has finished with, and Replace All leaves them alone.
- **A file open in a tab is edited through its document**, wherever it is
  open and whether or not the tab is dirty, so the tab is marked dirty and
  ⌘Z in that tab takes the replacement back as it does for any other edit. A
  file that is not open is rewritten on disk, atomically, only if it still
  holds what the search matched.
- **One ⌘Z in the list takes the whole replacement back**, files written to
  disk included, as long as each file still holds what the replacement left
  in it. A file edited since is left as it is and the status line says so.
- **The status line leads with a number**: `143 replaced in 27 files`, then
  what the re-run search still finds. A list that is a prefix of what is
  there — `more not shown` — refuses Replace All, because a replacement that
  stopped part-way through the project with nothing said is the failure the
  in-file Replace All was written to avoid.
- **The usages pane is untouched.** It is the same list over a different
  question, and the answer to "change every use of this symbol" is a rename
  through the language server, not a text replacement.

## Capabilities

### New Capabilities

- `replace-in-project`: replacing what the project search found — the replace
  half of the search pane, the key that opens it, which rows a Replace and a
  Replace All act on, how an open file and a closed one are written, what the
  replacement means under the switches, and the one undo.

### Modified Capabilities

- `search`: the pane's controls gain a row, and the purpose statement's "worked
  through rather than read" now includes changing a row; the requirement that
  marking done touches nothing on disk still holds and is restated beside the
  verb that does.

## Impact

- **AbydosKit** — `Sources/AbydosKit/Search`: a `ProjectReplace` that turns
  a file's current text, the question, the template and the marks chosen into
  one span edit per file, and the record an undo needs; `TextSearch.replaceAll`
  gains a way to leave a match out. Tests in `Tests/AbydosKitTests`.
- **AbydosApp** — `Panel/SearchPane.swift` (the replace row, the mode, the
  status), `Panel/ResultChecklist.swift` (the selection as marks, already
  there for ticking), `Panel/BottomPanel+Panes.swift` and
  `MainWindowController+Terminal.swift` (the verb and the menu item),
  `AppDelegate+Menu.swift`, and the editor's `document(for:)` for files that
  are open.
- **Driving**: `--search-steps` gains `replacing`, `replacement:<text>`,
  `replace` and `replace-all`, and `status` prints the replace state, so the
  claims about the pane can be checked from the command line on a scratch
  copy, never a real checkout.
- **Release notes**: one `##` in the next version's notes.
