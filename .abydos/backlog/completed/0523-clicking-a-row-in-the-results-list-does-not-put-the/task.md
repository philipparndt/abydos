# 523. Clicking a row in the results list does not put the keyboard in it

> it happens when directly click in the result tree. There is no issue when
> clicking on the tab before (but nobody will do this)

The reproduction, in the reporter's own words and much sharper than the one
0520 was filed on:

- Click **directly on a row** in the results list — the keyboard does not go
  there. ↑, ↓ and ⌫ go on reaching whatever had it before.
- Click the pane's **tab first**, then a row — it works.

Nobody clicks the tab first, so in ordinary use the list never takes the
keyboard from a click.

## Not what 0520 fixed

0520 was the ⇧⌘F **activation** path — `place(_:beside:focusList:)` had two
branches and only one read the parameter, so a deferred `focusList()` took the
keyboard back after `focusField()`. That is merged and is a different route:
this one starts from a click, and reaches `rowClicked`.

## What the click does today

`ResultChecklist.rowClicked` (`ResultChecklist.swift:255`) opens the row with
`ResultChecklistKeys.click`, which is `.permanent` — a tab of its own, and
deliberately **not** the keyboard, that being 0510's whole point: the hand that
clicked is over the list, and the next ⌫ must tick a row rather than delete a
character.

So the click is not *supposed* to move the keyboard to the editor. `AppKit`
should have made the table first responder on the mouse-down before any of this
runs, and `ChecklistTable.acceptsFirstResponder` is `true`
(`ResultChecklist.swift:760`). Something between those two facts is not
happening.

The reporter's own observation is the strongest lead in the item: **clicking the
tab first fixes it, and clicking the tab is the one gesture that does not open
anything.** That points at the open — `open(result, match, intent:)` →
`openFromChecklist` → `editor.open(fileURL:atLine:focusEditor: false)` — either
taking the keyboard despite `focusEditor: false`, or running while the table's
own first-responder change is still in flight and undoing it.

## Worth deciding

- **Whether a first click should open at all.** If the keyboard question turns
  out to be tangled with opening, the honest alternative is that the first
  click focuses and selects, and opening follows from the selection as it
  already does for ↓. That is a bigger change than a fix and should not be made
  by accident.

## What it turned out to be

**Nothing takes the keyboard back. Nothing ever gives it to the list.**

That is the whole answer, and it is why the item's own lead — the open — is
innocent. `open(result, match, intent:)` really does carry `focusEditor: false`
the whole way down, and `EditorViewController.activate` really does only call
`makeFirstResponder` inside `if focusEditor`. **But refusing to move the
keyboard to the editor is not the same as putting it in the list**, and
`rowClicked` never did the second thing. It relied entirely on AppKit having
already made the table first responder on the mouse-down.

AppKit does that — *when the window is key and the app is active*. When it does
not, the responder is still whatever had it when the click arrived, and then the
second half of the fault runs:

```swift
// EditorViewController.activate(index:focusEditor:)
contentArea.subviews.forEach { $0.removeFromSuperview() }
```

`removeFromSuperview` on a view that holds the window's first responder does not
move the responder along — **it resets it to the window itself**, which is
nobody. So with the caret in the editor, a click on a row left the window with
no first responder at all. Measured, from a build of this branch before the fix:

    who: CodeView        ← the caret in the editor
    click:7
    who: NSWindow  mine=false

and with the trace lines in that showed it happening:

    rowClicked enter      fr=CodeView       ← the table never became first responder
    activate enter        fr=CodeView
    activate after-remove fr=NSWindow       ← the removal above, dropping it
    rowClicked leave      fr=NSWindow

against a run where AppKit *had* done it, which is the same code passing:

    table become                            ← from the mouse-down
    rowClicked enter      fr=ChecklistTable
    activate after-remove fr=ChecklistTable ← nothing of the table's was removed
    rowClicked leave      fr=ChecklistTable

**And that is exactly the reporter's asymmetry.** Clicking the pane's tab ends in
`BottomPanel.giveKeyboard(to:)` → `pane.focusList()` → `makeFirstResponder`, so
after it the table *already* holds the responder — which is why the click that
follows works: there is nothing for AppKit to change and nothing of the table's
for `activate` to remove. Click a row first and both halves have to go right on
their own, and one of them is a coin toss.

So there are two faults, one per file, and each is fixed where it is:

1. **`ResultChecklist.rowClicked` now takes the keyboard for the list**, before
   anything is opened and before the ⇧/⌘ guards, because a ⇧-click that opens
   nothing is still a click in this list. Not the editor — the intent stays
   `.permanent`, which is item 510's rule and is what keeps ⌫ ticking a row.
2. **`EditorViewController.activate` no longer throws the keyboard on the floor**
   when it swaps content views. It asks, *before* the removal, whether the
   responder was inside the outgoing tab, and if it was and nobody asked for it
   to move, puts it in the tab now showing. It can only ever *keep* the keyboard
   in the editor — a responder outside `contentArea` never reaches that branch —
   so a row clicked with the keyboard in the list is untouched.

Fix 1 alone turns the panel transcript green (measured, six runs out of six).
Fix 2 is the hole underneath it, which would otherwise stay open for every other
open that says `focusEditor: false` while the editor holds the keyboard.

## Watched from outside the app

One binary per side, one script, in each of item 506's four homes. **The run must
not be a `--screenshot` run**: a capture run sets `NSApp.setActivationPolicy
(.accessory)` and never activates, and this fault is about what AppKit does on a
mouse-down. The scripts below drive a scratch fixture with no `--screenshot` and
kill the process by PID afterwards.

    --search needle
    --search-steps "place:<home>,settle:1.5,list,down,window-key:tab,settle:1,
                    who,click:7,settle:1,who,window-key:delete,settle:0.5,status"

`window-key:tab` puts the keyboard in the editor, which is the reporter's
starting position; `click:7` is the row; `window-key:delete` is ⌫ **sent at the
window**, so it also answers the question item 510 cares about — whether the key
gets to the list at all. It is new here: `pressAtWindowForTesting` had no ⌫,
which meant the one claim this fix must not break had no way to fail.

**Search — before**

    home     after ⇥      after the click            ⌫ at the window
    panel    CodeView     NSWindow        mine=false  nothing ticked   ✗
    sidebar  CodeView     NSWindow        mine=false  nothing ticked   ✗
    beside   CodeView     NSWindow        mine=false  nothing ticked   ✗
    window   ChecklistTable ChecklistTable mine=true  1 done           ✓

**Search — after**

    panel    CodeView     ChecklistTable  mine=true   1 done           ✓
    sidebar  CodeView     ChecklistTable  mine=true   1 done           ✓
    beside   CodeView     ChecklistTable  mine=true   1 done           ✓
    window   ChecklistTable ChecklistTable mine=true  1 done           ✓

The `window` home passes on both sides and is not a fault: `who` asks the
*list's own* window, and a list expanded into a window of its own never had the
editor's responder to lose. The same caveat items 510 and 520 wrote down.

**The usages list**, the same widget under the other heading — gopls over a
two-usage Go symbol, `--usages 5:6`, arriving with the keyboard in the rows as
its own rule says, then ⇥ out to the editor and a click back:

    before:  arrives ChecklistTable · ⇥ → CodeView · click → NSWindow       · ⌫ ticked nothing
    after:   arrives ChecklistTable · ⇥ → CodeView · click → ChecklistTable · ⌫ → 1 done

and after the fix in all four homes: `panel`, `sidebar`, `beside` and `window`
all end `ChecklistTable mine=true` with `· 1 done` on the heading.

**The tab first, which is the path that always worked**, so that the two agree:

    place:<home>,settle:1.5,list,who,click:7,settle:1,who,window-key:delete,status
    panel   ChecklistTable → ChecklistTable · 1 done
    beside  ChecklistTable → ChecklistTable · 1 done

`list` is `focusList()`, which is literally what the tab click calls — see
`BottomPanel.giveKeyboard(to:)` — so this is that gesture and not a stand-in for
it. Unchanged by the fix, which is the point.

**⌫ after a click still ticks a row, and that is in every line above**: `· 1
done` and `undo=Mark as Done` in the status line, from a ⌫ sent at the window
rather than at the table. Item 505 gave that key its meaning and item 510 made a
click keep the keyboard so it would be safe; this item is what makes it true
after a click that started somewhere else.

## The decision in "Worth deciding" was not taken

**A first click still opens.** The keyboard question turned out not to be
tangled with opening at all — the open is innocent, and the fix is one line in
the click and one in the tab swap. Making the first click focus-and-select, with
opening following from the selection the way it does for ↓, would have been a
change to what a click *means* in aid of a fault that was never about meaning.
Left where it is, undecided, for whoever wants it on its own merits.

## Ruled out on the way

- **The open taking the keyboard despite `focusEditor: false`.** The item's own
  prime suspect, and it is innocent. `.permanent` carries `focusEditor: false`
  from `openFromChecklist` through `EditorAreaController.open` to
  `EditorViewController.open` to `activate`, and `activate` only calls
  `makeFirstResponder` inside `if focusEditor`. Traced through with a line at
  every hop: on the runs that fail, the first responder entering `activate` is
  already wrong, so there was never anything for the open to steal.
- **`makeRoomForTheEditor`, which is deferred and looked exactly like the
  "in flight" shape.** It is a `DispatchQueue.main.async` around a divider
  move, so the suspicion was reasonable. It is not it: with a panel taller than
  half the window, so the deferred `setPosition` really runs, the transcript is
  identical. And the usages pane does not call it at all — its wiring goes
  straight to `openFromChecklist` — yet fails in exactly the same way, which
  rules it out from the other side.
- **A terminal beside the list grabbing the keyboard back.** `TerminalView`
  takes first responder in several places, and `makeRoomForTheEditor` ends in
  `tellTerminalsTheySizeChanged()`, so a terminal reacting to a resize was worth
  reading. None of its `makeFirstResponder` calls is on a resize path: they are
  a drop, a right-press, `mouseDown` and the testing hooks. Measured too — the
  `beside` home with a live shell fails and passes with the rest.
- **`CodeView` refusing to resign.** A first responder that answers
  `resignFirstResponder` with `false` makes `makeFirstResponder` fail silently,
  which would have explained "the keys keep reaching whatever had it" perfectly.
  Both `CodeView.resignFirstResponder` and `TerminalView`'s return `true`.
- **An event monitor or a `sendEvent` override intercepting the mouse-down.**
  There is none: no `NSEvent.addLocalMonitorForEvents` and no `sendEvent`
  override anywhere in the program.
- **A test in `AbydosKit`, the way item 510 extracted one.** There is no rule
  here to extract. Item 510 had a decision — which gesture means which intent —
  and this is a `makeFirstResponder` that was never called. A test of it would
  need a window, which is the layer the suite cannot reach, so the claim is made
  where it can fail: the transcripts above, and `window-key:delete`, which is
  the ⌫ half of it and is new.

## What the harness cost, and what it hid

- **A `--screenshot` run cannot see this fault.** `AppDelegate` sets
  `NSApp.setActivationPolicy(.accessory)` for a capture run, quite deliberately
  — "a capture run never takes the keyboard" — and under that policy AppKit's
  mouse-down responder assignment behaves differently and the driven click
  passes. Item 510's own transcript has `click:4 → who: ChecklistTable` for
  exactly that reason, from a build where a click *did* work. Anything measured
  about focus and the pointer has to be run without `--screenshot`.
- **`print` from a step is block-buffered when stdout is a pipe.** `who` and
  `rows` do not `fflush`; `status` and `heading` do. A script that ends on
  `rows` and is then killed by PID prints nothing at all, which reads exactly
  like the steps never running. End a driven script with `status` or `heading`.
- **The flag is `--usages`, not `--usages-at`.** An unknown `--flag` is skipped
  in silence, so the run looks like a language server that never answered.
- **`shift-click:` does not extend the selection under this harness**, whatever
  the fix. A posted ⇧-click reaches `rowClicked`, which correctly opens nothing,
  but the table's own selection extension does not happen in a run with no key
  window. Unchanged by this item — the claim made above is about the keyboard,
  which `who` answers, and not about the selection.

## Steps

- [x] Reproduce from outside the app: click a row with the keyboard in the
      editor, and print the first responder before and after — `who`,
      `--report-focus` and `window-key:` already exist
- [x] Find what takes the keyboard back, and say so here rather than describing
      the symptom
- [x] ⌫ can be sent at the *window* from a script, so "the click kept the
      keyboard" and "⌫ still ticks a row" are one claim and can fail
- [x] A click on a row puts the keyboard in the list, in all four homes
- [x] Clicking the tab first still works, and the two paths agree
- [x] Swapping the editor's content view does not drop the window's first
      responder — the hole under this item, found on the way
- [x] The usages list too, which shares the widget
- [x] `make test` and `make warnings` are clean — 2731 tests in 375 suites,
      no failures at all, and no warning in this repository's Swift. The two
      failures items 519 and 520 had to explain away both passed in this run:
      `runsAndWritesAThreeMF` builds the shared `abydos-examples` checkout,
      whose stray character somebody has since fixed, and
      `foldComputationIsReasonableOnHugeFile` measures the machine and had a
      quiet one
- [x] Write down here what was ruled out on the way, and what the harness
      itself hid — a `--screenshot` run cannot reproduce this at all
- [x] `spec/search.md` and `spec/usages.md` say what the project now does.
      Both were *wrong by omission* in the same way, and it is the omission
      the fault lived in: each said a click does not take the keyboard to
      the editor and neither said a click puts it in the list. Half a rule
      is what a click had implemented. Both requirements now say both
      halves and carry a scenario that starts with the keyboard somewhere
      else — which is the only shape of this that could ever fail

## Estimate

2026-08-17 — done
