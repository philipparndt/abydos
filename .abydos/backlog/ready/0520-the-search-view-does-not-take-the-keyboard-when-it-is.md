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

## What it is not

Not the freeze. 0519 is the live filter rebuilding everything on every batch,
which is a different file and a different fault.

## Steps

- [ ] Reproduce from outside the app: activate search, leave, activate again,
      and print the first responder each time — `who` and `--report-focus`
      already exist for this
- [ ] Find why the second activation differs from the first, and say so here
- [ ] Activating search puts the keyboard in it, every time
- [ ] The same for the usages list, which shares the widget
- [ ] Watched in each of 0506's four homes
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/search.md` and `spec/usages.md` say what the project now does
