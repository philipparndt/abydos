# 529. A search result shows as the selection moves, not only on Return

> and we should show the file on selection change and not only on return

The usages list already works this way. Search deliberately does not, and the
reporter — having just used both — wants the two to agree.

## The two specs say different things, on purpose

`spec/usages.md:102` — "↓ through a usages list shows each one and keeps the
keyboard". `spec/search.md:151` — "⏎ shows the selected match in the editor".

The difference is one line of code. `ResultChecklist` carries the whole
mechanism behind `opensOnSelectionChange`; `UsagesPane.swift:93` sets it true
and `SearchPane.swift:108` sets it false, with a comment giving the reason:

    // Search shows a result when it is asked to — ⏎ or a click — and not as
    // the selection moves. Walking a project-wide search with ↓ crosses files
    // nobody asked about, and the query is usually being refined rather than
    // worked through row by row.

That reasoning is not wrong, it is a judgement, and the person using it has
made the other one. Flip the flag and delete the comment — a comment defending
a decision that has been reversed is worse than none.

## What is already handled, and does not need building again

`selectionMoved(isARepeat:)` earns its keep here:

- **A held ↓ does not open a file per row.** A single press reveals at once; a
  repeat schedules the reveal 120ms out and each further repeat cancels the one
  before, so holding ↓ through a long result list opens exactly the row it
  stops on.
- **One tab, not one per match.** The walk uses the editor's provisional tab,
  replaced in place. ⏎ and a click still settle into a tab of their own.
- **A click does not preview *and* commit.** The preview is driven from the
  table's `keyDown` rather than from `selectionDidChange`, so a click opens once
  through the table's action.

So the concern the comment raises — crossing files nobody asked about — is
already bounded to the rows actually stopped on, which is exactly what usages
does across just as many files.

## Worth checking rather than assuming

- **A search still running.** Rows arrive while the list is live, and usages
  gets its list all at once. A row appearing under the selection, or the
  selection being restored as the model grows, must not fire a reveal —
  `restoringSelection` is the guard that exists, and whether it covers the
  live-append case is a question for the code and a test, not for this file.
- **⏎'s job afterwards.** It still opens in a tab of its own; showing a row that
  is already shown should not open it twice.
- **The scenario at `search.md:182`** spells out ↓, ↓, ⏎, ␣ and says the second
  row is shown. It stays true, but for a new reason — worth rewriting rather
  than leaving to read as though nothing changed.

## Steps

- [x] Flip `opensOnSelectionChange` for search and remove the stale comment
- [x] Lift the reveal decision out of the view into `ResultChecklistKeys`, where
      the live-append case can have a test
- [x] Moving the selection in the results shows that match; the keyboard stays
      in the list
- [x] A held ↓ through a long list opens one file, not one per row
- [x] A search still delivering rows does not reveal a row nobody moved to
- [x] ⏎ and a click still open a tab of their own and do not open twice
- [x] `spec/search.md` says the new rule, and the ↓↓⏎␣ scenario is rewritten to
      match; the two lists' specs agree or say plainly why they differ
- [x] `make test` and `make warnings` are clean
- [x] Write down here what was ruled out on the way

## What the live-append case turned out to be

**It was already safe, and not by the guard the item expected.** `restoringSelection`
is not what stops a batch of results from revealing a row: nothing routes a
reload-time selection change into `selectionMoved` at all. The reveal is driven
from `ChecklistTable.keyDown`, which compares the selection before and after
`super.keyDown` — there is no `tableViewSelectionDidChange` in this file and never
was, which is the decision item 470 made so that a click could not preview *and*
commit. A `reloadData` is not a `keyDown`, so a batch cannot reach the reveal
however it disturbs the table.

Two things underneath that, both worth having written down:

- **A batch cannot disturb the table anyway.** `ResultRows.append` puts the new
  rows past the end, so the index a selection holds names the same row before and
  after. `ResultRowsTests.abatchDoesNotMoveTheRowUnderAnIndex` is that claim, and
  it is the reason a reveal a held ↓ had scheduled is still the right one after a
  batch lands.
- **`restoringSelection` is held across the reload regardless**, and now that the
  rule is out in `AbydosKit` it has a test of its own. It is the guard for the
  paths where the view really does move the selection — `focusList` landing on
  the first heading, `takeKeyboardFromAbove` for ↓ out of the query field,
  `reload(keeping:)` after a row is ticked. Those are live and would reveal
  without it if the driving ever moved.

The decision is now `ResultChecklistKeys.revealing`, with four answers rather
than the view's three branches. The fourth is the one this item needed:
`notThisList` (nobody asked, and nothing scheduled is dropped) had to be separable
from `nothing` (somebody moved onto a heading, so drop what was scheduled). A
three-answer version would have made a batch cancel a held key's pending reveal.

## Ruled out

- **A `tableViewSelectionDidChange` delegate.** The obvious way to drive a
  preview, and the wrong one twice over: a click would preview and then commit
  through the table's action, opening the same file twice, and every reload
  during a streaming search would fire it. It was already rejected in item 470;
  it is rejected again here for the second reason as well.
- **Making `opensOnSelectionChange` a constant.** Both lists pass `true` now, so
  the flag looks dead. It is not: it is what
  `ResultChecklistKeys.opening` is asked in order to decide what ⏎ means, and the
  false case is the rule rather than a list nobody has. Deleting it would have
  meant deleting the parameter and the tests that pin ⏎'s two meanings.
- **Cancelling a pending reveal in `appendResults`.** Tempting and wrong. The row
  a held ↓ stopped on is still at the same index after a batch, so the preview
  lined up for it is still the right one; cancelling would mean a held ↓ through a
  search that is still running sometimes opens nothing at all. `setResults` does
  cancel, and that is the only place: a rerun throws the rows away, and a preview
  arriving afterwards would be showing a row out of an answer nobody is looking at
  any more.
- **Leaving `spec/search.md`'s "⏎ down a list in several files" scenario alone.**
  It said five ⏎ in five files leave one provisional tab. That was true only
  while ⏎ *was* the preview. ⏎ now settles a tab of its own, so five of them
  leave five tabs; the scenario is rewritten as the ↓ walk, which is what leaves
  one tab behind now.

## Watched from outside the app

A scratch fixture of six files, twelve matches, driven with `--search needle` and
`--search-steps`. Not a `--screenshot` run, and killed by PID.

    list,down,status,return-key,status,hold-down:7,settle:0.5,status,click:14,…

    opened=[src/file2.swift:2]
    opened=[src/file2.swift:2 src/file2.swift:2+]
    opened=[src/file2.swift:2 src/file2.swift:2+ src/file2.swift:4 src/file6.swift:4]

`list` lands on the first file heading and shows nothing. The first ↓ previews
(no mark). ⏎ over that same row settles it into a tab of its own (`+`), once.
`hold-down:7` crosses six rows and three files and opens **two**: the row the
first press landed on, and the row the key stopped on.

A separate run for the pointer, since a posted click needs the app activated:

    list,undo-key,down,status,click:4,status

    opened=[src/file2.swift:2]
    opened=[src/file2.swift:2 src/file4.swift:2+]

One entry for the click, and it is `+`. The click did not also preview — it does
not go through `keyDown`, which is the whole reason the reveal is driven from
there.

And the live-append case, observed rather than reasoned about:

    list,down,down,status,rerun,settle:2,status

    opened=[src/file2.swift:2 src/file2.swift:4]
    opened=[src/file2.swift:2 src/file2.swift:4]

`rerun` clears the list and streams all twelve matches in six files back into it
while a selection is sitting in the rows. Nothing was opened.
