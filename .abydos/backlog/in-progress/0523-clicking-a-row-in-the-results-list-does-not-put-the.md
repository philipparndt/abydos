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

## Steps

- [ ] Reproduce from outside the app: click a row with the keyboard in the
      editor, and print the first responder before and after — `who`,
      `--report-focus` and `window-key:` already exist
- [ ] Find what takes the keyboard back, and say so here rather than describing
      the symptom
- [ ] A click on a row puts the keyboard in the list, in all four homes
- [ ] Clicking the tab first still works, and the two paths agree
- [ ] The usages list too, which shares the widget
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/search.md` and `spec/usages.md` say what the project now does
