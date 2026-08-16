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

## Steps

- [ ] A click and a double click leave the keyboard in the list
- [ ] ⏎ leaves the keyboard in the list
- [ ] ⇥ is the one gesture that hands the keyboard to the editor
- [ ] A list without the keyboard draws its selection gray
- [ ] Watched from outside the app with `who` after each gesture, in both the
      search list and the usages list
- [ ] Watched in each of 0506's four homes, since ⇥ has other meanings there
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/usages.md` and `spec/search.md` say what the project now does
