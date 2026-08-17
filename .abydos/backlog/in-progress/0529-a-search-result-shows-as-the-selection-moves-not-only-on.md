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

- [ ] Flip `opensOnSelectionChange` for search and remove the stale comment
- [ ] Moving the selection in the results shows that match; the keyboard stays
      in the list
- [ ] A held ↓ through a long list opens one file, not one per row
- [ ] A search still delivering rows does not reveal a row nobody moved to
- [ ] ⏎ and a click still open a tab of their own and do not open twice
- [ ] `spec/search.md` says the new rule, and the ↓↓⏎␣ scenario is rewritten to
      match; the two lists' specs agree or say plainly why they differ
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
