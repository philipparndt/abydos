# 520. The search view does not take the keyboard when it is activated again

> there is a bug activating the search view. It does not get the focus after
> leaving it once

Open search, leave it, come back, and the keyboard is not in it. The first
activation is fine; every one after it is not.

Reported alongside 0519, which is the freeze, and this is the other half of the
same message — they are separate faults and 0519 is the one that cost a force
quit.

## Where to look first

**0510 landed an hour before this was reported and it is about exactly this.**
It made the keyboard stay in the list unless ⇥ is pressed, added a third
`Intent`, and made `.commit` take the project window's key status. Any of those
could leave the pane's idea of where the keyboard is out of step with the
window's — and "the first time works, the second does not" is the shape of a
state that is set once and never cleared.

Candidates, none confirmed:

- `SearchPane.focusList` and `focusField` — which one an activation asks for,
  and whether it asks at all on the second one.
- `BottomPanel` shows the pane and then focuses it asynchronously
  (`DispatchQueue.main.async { pane.focusList() }` at two call sites). An
  activation that is already showing may take a path that never reaches them.
- 0506 gave the list four homes, and `MainWindowController` grew a
  `focusList:` parameter on placement. A pane that is already in its home may
  be placed differently from one arriving.

**0510 is not it, and this section sent the next person to the wrong file.**
Left standing because it is what was believed when the item was written; see
*What it turned out to be* for what was measured instead. The third candidate is
the right one, one word out: it is not the *pane already being in its home*, it
is *which home*.

## What it is not

Not the freeze. 0519 is the live filter rebuilding everything on every batch,
which is a different file and a different fault.

## What it turned out to be

**`BottomPanel.place(_:beside:focusList:)` has two branches and only one of them
reads `focusList`.**

```swift
private func place(_ session: Session, beside: Bool, focusList: Bool) {
    if beside {
        putBeside(session, on: .right)   // ← focusList dropped here
        return
    }
    session.column = 0
    activate(session, focus: focusList)  // ← honoured here
    refreshTabs()
}
```

`putBeside` ended in an unconditional `giveKeyboard(to: session)`, which for a
results pane is `DispatchQueue.main.async { pane.focusList() }` — deferred by one
turn, because 0506 found that a responder set before the view is in a column is
set on a view with no window.

`showProjectSearch` — ⇧⌘F — asks for the pane with `focusList: false` on purpose
and then calls `pane.focusField()` itself, synchronously, because *asking is
typing a question*. So in the home beside the terminals the order was:

    panelPlace beside=true focusList=false
    giveKeyboard Search          ← the false was thrown away
    focusField                   ← the keyboard is in the query field
    …one turn later…
    focusList SEARCH             ← and it is taken straight back to the rows

The caret sat in the field and what was typed went to the table. From the
reporter's seat that is exactly "it does not get the focus".

**Why the first one works and the ones after do not.** Not a count and not a
state left set: it is the *home*. ⇧⌘F answers where the last ⇧⌘F answered, so the
first search of a session lands in the panel and is fine; once the list has been
sent to **Beside the Terminals** — which is one of the two homes this reporter
asked for by name in 0506 — every ⇧⌘F after that lands in the rows of the search
before it. The move itself puts the keyboard in the rows quite correctly, so what
is remembered is "it worked, and then it stopped".

**The same shape one door along, which nothing could see.**
`evictFromSidebar` pushes the other list out of the sidebar to make room, and it
was doing so with `focusList` defaulting to true — a list being evicted taking
the keyboard from the list arriving in its place. Measured before and after and
it makes no difference today: both moves defer by a turn and the arriving one is
queued second, so it wins on FIFO order. Fixed anyway, and said out loud in a
comment, because "it is right by accident of queue order" is not a thing to leave
for the next person.

**0510 is cleared, and it was the prime suspect.** Its three changes — ⇥ as the
only commit, the third `Intent`, `.commit` taking the project window's key status
— are all in `ResultChecklist`, `ResultChecklistKeys` and `openFromChecklist`, and
none of them is on the activation path at all. The activation path is
`findInProject` → `showProjectSearch` → `placeSearch` → `place` → `dock`, and it
reaches nothing 0510 touched. The fault predates 0510: it arrived with 0506, on
the day the `focusList` parameter was added and one of its two consumers was
missed. It was reported an hour after 0510 merged because 0510 is what made the
reporter go and use the list again.

## Watched from outside the app

Two binaries, one script, in each of 0506's four homes. `who` prints the window's
first responder — `NSTextView` is the query field's editor, `ChecklistTable` is
the rows — and `mine` says which of the two identical lists it is:

    --search diameterZZZ
    --search-steps "place:<home>,settle:1,who,list,down,window-key:tab,settle:1,who,again,settle:1.5,who"

`again` is ⇧⌘F through `findInProject`, which is the whole point: it is the same
door a keypress comes through.

**Before**

    home     moved there → ⇥ out    → ⇧⌘F again
    panel    ChecklistTable  CodeView  NSTextView      ✓
    sidebar  ChecklistTable  CodeView  NSTextView      ✓
    beside   ChecklistTable  CodeView  ChecklistTable  ✗
    window   ChecklistTable  —         NSTextView      ✓

The mechanism itself, from a build with a line in `focusField`, `focusList`,
`giveKeyboard` and `place`, on the `beside` run:

    panelPlace beside=true focusList=false
    giveKeyboard Search
    focusField
    focusList SEARCH            ← 40 ms later, and it wins

and on the `panel` run, which is why the panel home never failed:

    panelPlace beside=false focusList=false
    focusField

## Ruled out on the way

- **0510, the item's own prime suspect.** Above. Nothing on the activation path
  goes near it.
- **"An activation that is already showing never asks."** `showProjectSearch`
  calls `focusField()` every single time, unconditionally, and a trace on it
  shows it firing on every ⇧⌘F. The question was never whether it is asked for,
  it is who asks after it.
- **The panel being torn down and rebuilt on every ⇧⌘F.** It really is: with the
  search tab the only thing in the panel, `release()` empties the panel, which
  asks the window to hide it, and the dock that follows shows it again. It looks
  exactly like the bug and it is not — measured with a probe printing the pane's
  window, the first responder, the key window and `bottomPanel.isHidden` before
  the placement, after it, after `focusField`, one turn later and 600 ms later.
  The field holds it at every one of those points, with a terminal in the panel
  and without, on this fixture and on the abydos tree itself.
- **An early return in `place()` for "already in this home".** The obvious
  version of the fix, and it would have hidden the fault rather than fixed it:
  the `beside` branch would still drop `focusList` for every arrival that is not
  a no-op, and the return would then have to work out for itself whether the
  panel needs showing again.
- **The app not being frontmost hiding the fault.** Suspected, because
  `makeFirstResponder` and field editors behave differently in a key window.
  Checked from both sides: the panel home passes and the `beside` home fails
  identically whether the run has a key window or not.
- **Interactive reproduction with real keystrokes.** Tried first, since it would
  have been the most faithful; `osascript` on this machine has no accessibility
  permission and cannot send keys. `--search-steps` has an `again` verb that
  calls `findInProject(nil)`, which is the same door, so nothing was lost.
- **A rule extracted into `AbydosKit` with a test, the way 0510 did it.** There
  is no rule here to extract. 0510 had a decision — which gesture means which
  intent — and this is a parameter that one of two branches failed to pass on.
  A test of it would be a test that `false` is still `false`. The claim is made
  where it can fail instead, in the four transcripts above.

## Steps

- [x] Reproduce from outside the app: activate search, leave, activate again,
      and print the first responder each time — `who` and `--report-focus`
      already exist for this
- [x] Find why the second activation differs from the first, and say so here
- [ ] `who` says *which* list holds the keyboard, since search and usages are
      the same class and the type alone cannot tell two `ChecklistTable`s apart
- [ ] Activating search puts the keyboard in it, every time
- [ ] The same for the usages list, which shares the widget — its rule is the
      other one, the rows, and it still holds
- [ ] A list evicted from the sidebar does not take the keyboard from the list
      arriving in its place
- [ ] Watched in each of 0506's four homes
- [ ] `make test` and `make warnings` are clean
- [x] Write down here what was ruled out on the way
- [ ] `spec/search.md` and `spec/usages.md` say what the project now does

## Estimate

2026-08-16 22:10 — the fault is found; about an hour left for the fix, the
four homes and the spec
