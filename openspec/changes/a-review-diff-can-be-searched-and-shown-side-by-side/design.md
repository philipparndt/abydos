## Context

See proposal.md for why. The pieces this is made from are already here:

- `DiffView` (`Sources/AbydosApp/Git/DiffView*.swift`) draws a `GitPatch` as
  `rows`, either `.line` rows (unified) or `.pair(left:right:)` rows (side by
  side), rebuilt by `rebuildRows()` whenever the patch, the remarks or a diff
  preference changes. It already answers `text(ofRow:in:)` for a row and a
  column — the code without git's prefix — because `DiffTextRun` selects and
  copies through it, and it already draws a character range behind a row's
  glyphs (`highlight(rowAt:in:at:)`). It neither wraps nor scrolls sideways:
  a line wider than the pane is clipped.
- `isSideBySide` is read from `Settings.diffIsSideBySide` in
  `applyDiffSettings()`, which every `DiffView` runs off the settings
  notification. The pull request page therefore already follows the View menu;
  nothing on the page sets it.
- `FindBar` is a plain `NSView` with callbacks (`onQueryChanged`, `onNext`,
  `onPrevious`, `onClose`), `setStatus(matchCount:currentIndex:)`,
  `setReplacing(_:)` and `wantedHeight`. Nothing in it knows about the editor.
- `TextSearch.matches(in:query:options:)` in AbydosKit turns a text, a query
  and `SearchOptions` into UTF-16 ranges with line and column, capped at
  `matchLimit`.
- ⌘F is Edit ▸ Find…, sent to the first responder as `findInFile(_:)`.
  `SettingsPage` and `BranchesPane` answer it themselves from inside the
  responder chain; anything that does not falls through to
  `MainWindowController.findInFile`, which asks the editor and gets nothing on
  a page.

## Goals / Non-Goals

**Goals:**

- One definition of "a match in a diff", in AbydosKit, tested without a window.
- `DiffView` holds a query and its matches, draws and reveals them, and runs
  the query again after every rebuild; it does not host a bar or know what a
  pull request is. (Changed while building it — see "`DiffView` holds the
  search" below.)
- The page and the View menu cannot disagree about side by side.

**Non-Goals:**

- Searching every file of a pull request at once. That is a results list, not a
  find bar — the shape `search` already has for the project — and a checked-out
  pull request can already be searched with ⇧⌘F.
- Find in the changes pane, the log page's commit view or the stash page. They
  use the same `DiffView` and can host the same bar later with a few lines
  each; doing it here would triple what has to be driven to call this done.
- Find in the compare page's `FileCompareView`. It is a different view with
  folded runs, and searching into a fold is a question of its own.
- Wrapping or sideways scrolling in `DiffView`.
- A key for the side-by-side switch.

## Decisions

### What is searched is the rows' own text, one line at a time

The searchable text of a diff is built from the rows `DiffView` already has:
for each code row and each column it draws code in, the line's text without
git's prefix. `DiffSearch` in AbydosKit takes those lines and a query with
options, compiles the pattern once with `TextSearch.makeRegex` — so case, whole
word and regular expression mean what they mean in the editor — and matches it
against each line, answering `(line index, utf16Range)`. The view maps the line
index back to `(row, column)`. A match of no characters is dropped, and the
editor's match limit applies.

**Changed while building it: per line, not joined.** The first plan joined the
lines with newlines and ran `TextSearch.matches`, mapping its line numbers back
to rows. That map goes through `TextSearch`'s own idea of where a line breaks,
and a diff of a CRLF file carries a lone `\r` inside a line's text — which would
shift every row after it. Per line, a match cannot span two rows whatever the
pattern says, so nothing has to be dropped after the fact either.

**Side by side, an unchanged pair contributes its right half only.** Context
lines are equal on both halves by definition, so the left half adds nothing but
a second count. Removed and added halves both contribute.

Ruled out:

- **Searching the patch text (`GitPatch` lines) and mapping back to rows.**
  Rows are what is drawn and selected; the patch is one step removed, and the
  side-by-side pairing is a fact about rows, not about the patch. Mapping patch
  indices to rows already exists in pieces (`Side.index`) but would be a second
  place for "which half is this on" to be got wrong.
- **A pattern of its own, built per row.** What would have killed matching per
  line was a second copy of the whole-word and regex rules `TextSearch` keeps,
  and a compile per row. Neither is paid: the pattern is `TextSearch`'s, built
  once per query, and only the matching is per line.
- **Including remark rows.** A remark is prose about the code, drawn as rows
  under it; a search for an identifier that lands in somebody's paragraph moves
  the reader away from the code they were searching. If people ask for it, it
  is a switch on the bar later, not a default.

### `DiffView` holds the search; the page holds the bar

`DiffView` gains `search(for:options:)`, `stepMatch(by:)` and `endSearch()`,
in `DiffView+Search.swift`, and runs the query again at the end of every
rebuild: `setDiff`, `setComments` and `applyDiffSettings`.

**Changed while building it.** The plan was for the page to hand matches in and
to re-run the search after each thing it does. But the rows are rebuilt by a new
file, the whole-file switch, a remark being written, the View menu's side by
side, and a zoom — two of which do not go through the page at all. Holding the
query where the rebuild happens is the one place that sees every one of them.
What a match *is* stays in AbydosKit, so the view still decides nothing about
that. Drawing
puts a match colour behind each match on visible rows (the same
`Theme.current` find colours the code view uses, so a match looks like a
match), a stronger one behind the current, using the geometry `highlight`
already uses for the text selection. Revealing scrolls the row into view and
sets the text selection to the match through `textRun`, so ⌘C, the menu and
"the last gesture wins" behave as `diff-selection` already says.

Drawing walks only matches on visible rows: matches are kept sorted by row and
the visible row range is binary-searched, so a `.` search capped at 5,000
matches costs nothing on a frame that shows forty rows.

The page owns a `FindBar` above the diff scroll view (hidden, zero height,
until ⌘F), answers `findInFile(_:)`, `findNext(_:)` and `findPrevious(_:)`, and
shows `n of m` when the view says its matches moved. The wiring goes in
`PullRequestPage+Find.swift`, keeping the page under the length limit.

Ruled out:

- **The search living in `DiffView`, bar and all.** `DiffView` is at four files
  already because of the 1,100-line ceiling, is shared by three hosts, and is
  laid out by whoever embeds it; a bar inside a scroll view's document view
  scrolls away with the text.
- **A new bar for diffs.** Two find bars that look the same and differ in
  keys, wrapping or status wording is the outcome this avoids; `FindBar` has
  nothing editor-specific in it.

### The current match after a rebuild

A rebuild invalidates row indices. Before rebuilding, the view remembers the
current match by what survives a rebuild: its column side (old / new), the line
number on that side, and its offset in that line. After the rebuild it looks
for a match with the same three; if found, it stays current, otherwise the
first match at or below the top visible row is current. The same
`(side, line number)` key keeps the reader's place across the arrangement
switch: the top visible row's line number is remembered and the row holding it
afterwards is scrolled to the top.

**A switch does not undo the place it just kept.** Scrolling to the current
match after the switch, as every other rebuild does, took a reader who had
scrolled away from it straight back — a driven run showed the top row going
from new line 298 to 453. So after a switch the match is followed to its new row
only if it was on screen before.

Which file a diff is of is passed to `setDiff` as an `identity` (its URL): the
same file — the whole-file switch — keeps the current match, and a different
one starts again, where a match at the same line and offset is a coincidence.

A removed line has no new-side number, so the key uses whichever side the row
has; a top row that is a hunk header or a remark takes the nearest code row
below it.

Ruled out: **remembering the match's index (`4 of 7`).** It is right only when
the rebuild changes nothing about which lines are searched — true for the
arrangement switch, false for *Whole file*, which adds lines above the change.

### Side by side is the one setting, and the menu reads it

The page's switch is a `DrawnCheckbox` beside *Whole file* that toggles
`Settings.diffIsSideBySide`; the page listens for the settings notification and
sets the switch from the setting, so a menu flip moves it. The View menu item's
tick moves from "set when built and when chosen" to
`MainWindowController.validateMenuItem`, which is what keeps every other ticked
item here honest — otherwise flipping the page's switch leaves the menu ticked
the wrong way until the next relaunch.

Ruled out:

- **A per-page arrangement.** The request was "the option to toggle", and one
  could argue a review wants pairs while the changes pane wants one column. But
  two places that answer "is this diff side by side" differently is the thing
  people then file as a bug — the menu would tick one answer while the page
  showed another — and nothing in the request asked for the two to differ. If
  it is wanted it is a second setting later, and this change does not make that
  harder.
- **A segmented *Unified | Side by side* control.** The page's other binary
  choices are checkboxes; the arrangement control is segmented because it
  names two equal arrangements of a list. A checkbox is less to read in an
  already full row.

### Driving

`PullRequestReview.driveForTesting` gains `find:<query>`, `find-next`,
`find-previous`, `find-status` (what the bar says, and the current match's row
and range), `find-close` and `side-by-side:on|off`, so the scenarios in both
specs are run by a driven launch against a scratch repository and not only by
reading the code. The existing `PAGE side-by-side:` driving in
`SidebarController+PageDriving.swift` sets the setting directly and stays.

## Risks / Trade-offs

- **[The find bar does not follow the zoom]** — at 1.6× the strip is taller
  but its field and switches stay small. This is how `FindBar` already behaves
  over the editor; fixing it is a change to the editor's bar too, and is not
  made here.
- **[A match past the right edge of a long line cannot be shown]** — closed
  by `a-diff-scrolls-sideways`: each text column now scrolls sideways, and the
  reveal brings the current match into view horizontally as well.
- **[Side by side in a narrow pane]** — the diff is the right-hand side of a
  split; two halves of it are narrow on a laptop. → The split divider is
  already draggable. Nothing switches arrangement automatically by width: a
  view that changes shape when a window is resized is harder to read than a
  narrow one.
- **[Search cost on a whole-file diff of a large file]** — building the joined
  text and running the regex is linear in the file and happens per keystroke.
  → `FindBar` already debounces as the editor does; `TextSearch` caps matches;
  the pattern is compiled once per keystroke. Measured: 3.7 ms over 20,000 lines
  in a debug build, at load 0.3 per core
  (`DiffSearchTests.aKeystrokeOverATwentyThousandLineDiffIsCheap`).
- **[The menu tick moving to validation]** — `AppDelegate+DrivenEditor` reads
  `validateMenuItem` for driven menu checks; the item's state now changes there
  too. → Covered by the driven `side-by-side:` step reading the menu.
