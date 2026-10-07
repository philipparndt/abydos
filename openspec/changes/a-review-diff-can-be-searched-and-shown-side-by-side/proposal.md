## Why

Asked for on 2026-10-05, about the pull request page: "I want to have 1st that
I can search in the diff view for text as in a normal text file. 2nd I want to
have the option to toggle to a diff view that is not in place but side by side."

**⌘F on a pull request page does nothing.** Edit ▸ Find… goes to
`MainWindowController.findInFile`, which asks the editor group for its find bar,
and `EditorViewController.showFind` returns unless the front tab has a code view
or a PDF. A page has neither, so the key is swallowed without a sound. The
settings page and the branches pane each answer `findInFile(_:)` themselves
from inside the responder chain; the pull request page does not, and neither
does `DiffView`. A reviewer looking for every place a renamed symbol still
appears in a two-thousand-line file reads it by eye, or checks the branch out
and opens the file as a tab — which loses the diff they were searching *in*.

**Side by side exists and cannot be found from the page.** `DiffView` has drawn
pairs since `diff-selection` was written, behind `Settings.diffIsSideBySide`,
and the pull request page already follows it. The only way to it is View ▸ Diff
▸ Side by Side Diff, two submenus away from a page whose own controls — *Whole
file*, *Hide read*, the arrangement — sit in a row at its top. Asking for a
feature that is already built is the evidence: nothing on the page says it is
there. The menu item has a second fault this would make worse: its tick is set
when the menu is built and when the item itself is chosen, so anything else
that flips the setting leaves the menu saying the opposite of the screen.

There is no originating `.abydos/backlog` item: the backlog is retired and this
comes from a direct request.

## What Changes

- **⌘F on a pull request page opens a find bar over the diff.** The editor's
  `FindBar` — the same field, match case, whole word and regular expression —
  in find-only form, above the diff. Every match in the file shown is marked,
  the current one is scrolled into view and selected, `n of m` is shown, and
  ⌘G / ⇧⌘G / Return / ⇧Return step through them, wrapping. ⎋ closes it.
- **The query outlives the file.** Choosing another file in the list, turning
  *Whole file* on or off, or switching the arrangement runs the same query over
  what is now shown, so a reviewer walking the files with one question keeps it.
- **What a match is, in a diff.** The text of the code lines, without the
  `+`/`-`/space git puts in front of them. Removed and added lines are both
  searched. Side by side, an unchanged line drawn on both halves is one match,
  not two.
- **A *Side by side* switch on the page**, in the row of controls beside
  *Whole file*. It is the same setting the View menu flips — one answer to one
  question, in every diff in the window — and the menu's tick is made to read
  the setting rather than remember its last click.
- **Switching keeps the reader's place.** The line at the top of the diff is
  still at the top after the switch, and a search that was open keeps its query
  and its current match.

## Capabilities

### New Capabilities

- `diff-search`: finding text in a diff the way a file is searched — what is
  matched, how matches are marked and walked, and how a search survives the
  diff under it being rebuilt.

### Modified Capabilities

- `pull-requests`: the page offers the find bar over its diff and a switch
  between the unified and side-by-side arrangements, and keeps the reader's
  place across the switch.

## Impact

- `Sources/AbydosApp/Review/PullRequestPage.swift` — hosts the find bar, answers
  `findInFile(_:)`, `findNext(_:)` and `findPrevious(_:)` from the responder
  chain, and gains the switch. It is 874 lines against the 1,100 that
  `Scripts/file-size.sh` keeps, so the find wiring is likely to go to an
  extension of its own.
- `Sources/AbydosApp/Git/DiffView*.swift` — takes a set of matches and a current
  one, draws them, and scrolls one into view. The view is shared with the
  changes pane and the log page; they gain nothing visible from this change but
  can host the same bar later.
- `Sources/AbydosApp/Editor/FindBar.swift` — used as it is, with the replace
  row kept hidden; no change expected beyond what hosting it outside the editor
  needs.
- `Sources/AbydosKit/Search/` — a pure mapping from a diff's searchable lines to
  matches, on top of `TextSearch`, so what counts as a match is tested without a
  window.
- `Sources/AbydosApp/AppDelegate+Menu.swift`, `MainWindowController+Layout.swift`
  — the Side by Side Diff item's tick validated rather than stored.
- `PullRequestReview.driveForTesting` — steps to drive the find bar and the
  switch, so both are checked in a driven run.
- No new dependency, no new setting.
