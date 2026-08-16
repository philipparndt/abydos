# 510. A results list keeps the keyboard until Tab, and says when it has not got it

> the search/references view is still not working: The focus is in the search
> view, but all keyboard inputs are going to the code editor (like up/down/delete)

Reported with a screenshot: a search for `diameter`, a row selected and
highlighted in the results, and ↑, ↓ and ⌫ all going to the editor behind it.
The list looks like it has the keyboard. It has not.

**This is now expensive rather than merely confusing.** 0505 gave ⌫ a meaning
in this list an hour before the report. A person who believes the keyboard is
in the list presses ⌫ to tick a row off and deletes a character of their source
instead — the reported screenshot has the dirty dot on `main.swift`.

## Why it happens, and why it survived

It is written down. `ResultChecklist` opens a clicked match with
`intent: .commit` — *"Somebody who clicked a line of code means to be in it"* —
and `spec/usages.md` says the same in prose:

> The deliberate way into the editor is **⏎** or **⇥**. Both open the selected
> usage and hand the keyboard over. A click and a double-click do the same,
> because somebody who clicked a line of code means to be in it.

So the keyboard leaving on a click is the documented behaviour. What is not
documented, and is the other half of the fault, is that **nothing on screen
changes when it leaves**: the row keeps the same highlight whether the list has
the keyboard or not, so there is no way to tell the two states apart.

## The decision, in the reporter's own words

Asked which way to fix it, Philipp answered on 2026-08-16:

> the keyboard fokus stays in the list unless tab is pressed. Also when there is
> no focus the selection color changes to gray.

Taken literally, and it should be: **⇥ is the only thing that hands the keyboard
to the editor.** A click keeps it. A double click keeps it. **⏎ keeps it** —
that is the part that reverses the spec sentence above, and it is deliberate,
not an oversight in the answer. Everything still *shows* the row it opens; what
changes is who has the keyboard afterwards.

And an unfocused list draws its selection **gray**, so the state is never a
guess.

## The same rule in the editor, asked for in the same breath

> the selection color would change would also be nice for the source editor
> currently it looks like this: [screenshot] while the focus is in the terminal

The screenshot shows several lines of Markdown selected in the strong
highlight, with the keyboard in the terminal below. Same fault, one view over,
and it is older than any of today's work: **a selection is drawn as though its
view has the keyboard whether or not it does.** `CodeView` is where that one
lives, and it is the same in every editor pane — a split, a diff, the commit
message field — wherever a selection is drawn.

So this item covers both, deliberately: the gray has to be *one* colour and
*one* rule, and two agents inventing it separately in two files is how a
program ends up with two grays that nearly match. `Theme` is where the colour
belongs rather than either view.

## What this changes in the spec

Two sentences in `spec/usages.md`, and whatever `spec/search.md` says to match:
⏎ is no longer a way into the editor, and a click no longer does what a double
click does — or rather they now agree in the other direction, both keeping the
keyboard. The requirement's name, "↓ through a usages list shows each one and
keeps the keyboard", survives and gets stronger.

## What exists to build on

- `ChecklistTable.becomeFirstResponder` / `resignFirstResponder` already set
  `needsDisplay`, so the redraw hook for the gray selection is there.
- `ResultChecklist.Intent` is already the two-valued thing being decided —
  `.preview` keeps the keyboard, `.commit` hands it over. This is largely a
  question of which gesture produces which, not new machinery.
- `stepForTesting` has a `who` verb that prints the window's first responder,
  which is how any claim here gets checked. 0506 added `window-key:<key>` for
  keys sent at the window rather than into the table, which is the honest way
  to prove where they land.

## Worth deciding

- **What ⇥ does when the list is in the sidebar or beside a terminal.** 0506
  landed four homes an hour ago. ⇥ is also how the key view loop moves between
  controls, and in search it has always walked to the query field.
- **Whether the gray is the system's inactive selection or a colour of this
  program's own.** `NSTableView` has an answer; the panel is themed.

## What it turned out to be

**Two intents could not say what was asked for.** `Intent` was
`.preview`/`.commit`, and `.commit` meant two things at once: a tab of its own
*and* the keyboard going with it. `spec/search.md` promises a click a permanent
tab, and the decision says a click keeps the keyboard — so "a click" is a third
case, not a flip of the two. Flipping `.commit` to `.preview` at the click, which
is the one-line fix this item looks like, would have quietly turned every clicked
result into the provisional tab that the next click replaces. So:

| | tab | keyboard |
|---|---|---|
| `.preview` — ↓ down a usages list, ⏎ in search | provisional | stays in the list |
| `.permanent` — a click, a double click, ⏎ in usages | its own | stays in the list |
| `.commit` — **⇥, and nothing else** | its own | goes to the editor |

The rule that turns a press into one of those is
`ResultChecklistKeys.opening`, beside `marksDone` in `AbydosKit` and there for
the same reason: nothing in the window layer has a test, and this is the other
half of that hazard. ⌫ means *done* in this list, and that is only safe while
the keyboard is provably still in it.

**⇥ in search.** It used to walk the key view loop to the query field. It now
commits, in both lists: with ⏎ and the click no longer handing over, search would
otherwise have had no keyboard route into the editor at all. ⇧⇥ is deliberately
not answered, so the way back up to the field is still there.

**The one home where ⇥ was a lie.** A list expanded into a window of its own is a
second window, and it is the key one while somebody works the list.
`editor.open(…)` made the `CodeView` the *project* window's first responder and
stopped — so ⇥ opened the file, the caret blinked in it, and every keystroke went
on reaching the panel. Measured, not guessed: `FOCUS 9.0s ChecklistTable in
ResultsWindow` after a ⇥ that had reported `opened=[shapes.swift:6!]`. That is
this item's own fault one window over, and `.commit` now makes the project window
key. The same run afterwards says `FOCUS 9.0s CodeView in NSWindow`.

**The gray is `selectionInactive`, the scheme's own.** Not the system's inactive
selection, and not a new scheme key. The project tree has drawn its unfocused
rows in it since long before today — which is both the precedent and the evidence
that it reads as gray in all three schemes — and a themed panel beside a system
gray is two programs in one window. `Theme.selection(_:hasKeyboard:)` is now the
only place that decides it, for a row and for a run of text, and the tree asks it
too.

**The half that would have gone wrong quietly.** `ChecklistTable`'s
`needsDisplay` was already there but reaches neither the row view nor the cell
inside it, and `ChecklistMatchCell` draws its text near-white when the row is
selected. Near-white on the pale gray of a light scheme is unreadable, so the
cell now asks whether the list has the keyboard as well as whether the row is
selected, and both are invalidated on the way in and out.

## Ruled out on the way

- **Flipping the click from `.commit` to `.preview`.** The whole of the change,
  in one line — and wrong: it would have moved every clicked result into the
  provisional tab, against `spec/search.md`. This is why there are three intents.
- **A new scheme key for the unfocused text selection.** It would have meant
  `Scheme.swift`, three JSONs and a derivation rule in `SchemeLibrary` for
  schemes that omit it, and it would have made two grays where the item asks for
  one. `selectionInactive` behind code reads as a dimmed band in all three
  schemes; the screenshots below are the abydos dark one.
- **Requiring the window to be key as well, for the gray.** `hasKeyboard` is
  "this view is its window's first responder" and deliberately not "…and the
  window is key". macOS would gray everything when the app goes to the back, but
  every `--screenshot` run in this project is unattended and has *no* key window
  at all — so that rule would have made every screenshot the toolkit takes show
  gray selections everywhere, including the ones this item is judged by. The
  project tree has always drawn it this way too.
- **`CodeView.becomeFirstResponder` not marking itself for redraw.** Read as a
  trap and checked: it does, through `restartCaretBlink`, which ends in
  `needsDisplay = true`. Nothing was added; the reliance is now said out loud at
  the call, because a redraw narrowed to the caret rect later would leave the
  selection gray with the keyboard in the view.
- **`window-key:tab` against the old binary.** The before/after transcripts below
  are honest about this: the pre-fix `pressAtWindowForTesting` had no `tab` in
  its key table, so a `window-key:tab` sent at it did nothing at all. The old ⇥
  was driven with `tab-key`, which goes straight to the table.

## Watched from outside the app

Two binaries, the same scripts. `who` prints the window's first responder;
`opened=[…]` is what the list believes it opened, with `+` for a tab of its own
and `!` for the keyboard going with it.

**The search list, before** — `--search diameter`, then a click, ↓, ⏎ and ⇥ sent
at the *window*:

    who: NSTextView          opened=[]
    click:4  → who: CodeView opened=[shapes.swift:3!]
    ↓        → who: CodeView opened=[shapes.swift:3!]
    ⏎        → who: CodeView opened=[shapes.swift:3!]

The whole report is in those four lines. After the click the keyboard is in the
editor, and ↓ and ⏎ *sent at the window* never reach the list again — which is
why nothing further opens. ⌫ in that state edits the file.

**The same script, after:**

    who: NSTextView              opened=[]
    click:4  → who: ChecklistTable opened=[shapes.swift:3+]
    ↓        → who: ChecklistTable opened=[shapes.swift:3+]
    ⏎        → who: ChecklistTable opened=[shapes.swift:3+ shapes.swift:5]
    ⇥        → who: CodeView       opened=[… shapes.swift:5!]

**The usages list**, gopls over a five-usage symbol, before and after:

    before: arrives ChecklistTable · ↓ → ChecklistTable [main.go:6] · ⏎ → CodeView [… main.go:6!]
    after:  arrives ChecklistTable · ↓ → ChecklistTable [main.go:6] · ⏎ → ChecklistTable [… main.go:6+] · ⇥ → CodeView [… main.go:6!]

**⇥ in each of 0506's four homes**, one run, moving the list between them:

    where=sidebar  ⇥ → who: CodeView        opened=[shapes.swift:3!]
    where=beside   ⇥ → who: CodeView        opened=[… shapes.swift:5!]
    where=window   ⇥ → who: ChecklistTable  opened=[… shapes.swift:6!]
    where=panel    ⇥ → who: CodeView        opened=[… shapes.swift:11!]

The window home is the odd one and needed reading carefully: `who` asks *the
list's own window*, and a results window that is no longer key goes on
remembering that its own first responder was the table. The question is which
window is key, which is what `--report-focus` answers — and it said
`ChecklistTable in ResultsWindow` until `.commit` was made to take the project
window's key status as well.

## The pictures

- `images/before-list.png` — the reported fault, from a build of this branch
  before the fix: the row in the strong highlight, `who: CodeView`. It is
  pixel-for-pixel what a focused list looks like.
- `images/list-focused.png` — the same row with the keyboard actually in the
  list.
- `images/list-gray.png` — after ⇥. Same selection, gray band, and the text back
  to its ordinary colour rather than the near-white.
- `images/editor-strong.png` and `images/editor-gray.png` — the second half of
  the report: six lines of Markdown selected, with the keyboard in the editor and
  then in the search field. Same selection, two colours.

## Steps

- [x] A third intent, because two will not say it: `Intent` decides the
      keyboard **and** whether the tab is provisional, and "a click keeps the
      keyboard but still opens a permanent tab" is a case neither of the two has
- [x] A click and a double click leave the keyboard in the list
- [x] ⏎ leaves the keyboard in the list
- [x] ⇥ is the one gesture that hands the keyboard to the editor
- [x] The rule is one function in `AbydosKit` with a test, since nothing in the
      window layer has one
- [x] `window-key:tab`, so the ⇥ claim can be made where it can fail — the
      existing `tab-key` calls the table directly and proves nothing about
      whether ⇥ ever reached it
- [x] A list without the keyboard draws its selection gray
- [x] The **editor** does the same: a selection in a `CodeView` that has not
      got the keyboard is gray too, which is the second half of the report
- [ ] `CodeView.becomeFirstResponder` marks itself for redraw — today only
      `resign` does, so a focus-dependent colour would gray on the way out and
      stay gray on the way back in

      Not done, because it already did. `becomeFirstResponder` calls
      `restartCaretBlink`, which ends in `needsDisplay = true`; the gray comes
      back on the way in without any change. Left here rather than deleted
      because it was read as a trap and is not one, and because the reliance is
      now a comment at that call.
- [x] One colour and one rule for both, named once in `Theme` rather than
      decided twice — and the project tree, which has been doing this by hand
      since long before today, asks the same function
- [x] Watched from outside the app with `who` after each gesture, in both the
      search list and the usages list
- [x] Watched in each of 0506's four homes, since ⇥ has other meanings there
- [x] ⇥ from a list in a window of its own takes the project window's key
      status too, which the watching found it was not doing
- [x] Screenshots of the gray, in both views, since this is judged by eye
- [x] `make test` and `make warnings` are clean
- [x] Write down here what was ruled out on the way
- [x] `spec/usages.md` and `spec/search.md` say what the project now does, and
      `spec/editor.md` says what the editor's own selection does
