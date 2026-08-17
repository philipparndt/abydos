<!-- What this item changes about `usages`. Folded into
     .abydos/backlog/spec/usages.md by `abydos-backlog done`. -->

## MODIFIED Requirement: ↓ through a usages list shows each one and keeps the keyboard

Moving the selection in a usages list shows that usage: the editor unfolds it,
puts the caret on it and brings it on screen — down the page and, on a long line,
across it, and without moving the view for a usage that is already showing. The
rule is `editor.md`'s and it is the same one a search result gets, because the two
lists are one widget and a place in a file is a place in a file. The keyboard stays in the list, so ↓
reaches the next usage and ␣ ticks the one just looked at. Looking at each of a
list of usages is a different intention from working on one of them, and only the
second costs the keyboard.

**⇥ is the only gesture that hands the keyboard to the editor.** ⏎, a click and a
double-click all *show* the usage — in a tab of its own, not the provisional one
— and all leave the keyboard in the list. A hand that has just clicked a row is
over the list, and its next ⌫ has to tick that row off rather than delete a
character of the file: ⌫ means "done" here, and that is only safe while the
keyboard is provably still here. ⇧⇥ is not a way out either; it goes on walking
the key view loop.

**A click brings the keyboard to the list, and does not merely leave it alone.**
Where it was before the click makes no difference — the editor, a terminal, or
nowhere. "The click does not take the keyboard to the editor" and "the click puts
the keyboard in the list" are one rule, and a list that only kept the first half
answered ⌫ with whatever the hand had been typing into a moment earlier.

An unfocused list says so. A selected row is drawn in the strong highlight only
while the list has the keyboard, and in the same gray as an unfocused row in the
project tree once it has not — so "the list looks live" and "the list is live"
are never two different things.

The file shown as the selection moves is the editor's **provisional tab** — the
one the project tree's single click uses — replaced in place by the next one. So
walking a list of any length leaves one tab behind, not one per usage. ⏎, a click
and ⇥ each settle what they open into a tab of its own.

A key held down does not open a file per row. The first press of a held key shows
its row at once; while the key is repeating nothing is shown, and the row it
stops on is shown when it stops. So ↓ held through 263 usages opens one file. A
row already showing is not opened again.

### Scenario: walking a list without the mouse

- **Given** a usages list with the keyboard in it
- **When** ↓ is pressed three times
- **Then** the third usage is shown in the editor with the caret on its line, and
  the keyboard is still in the list

### Scenario: ticking one off after looking at it

- **Given** the same list, having just pressed ↓
- **When** ␣ is pressed
- **Then** that usage is struck through and nothing is typed into the file

### Scenario: ⏎ over a usage

- **Given** a usage selected and showing in the editor
- **When** ⏎ is pressed
- **Then** its tab is no longer provisional, and the keyboard is still in the
  list — so the next ⌫ ticks the usage off rather than editing the file

### Scenario: clicking a usage

- **Given** a usages list with the keyboard in it
- **When** a row is clicked
- **Then** that usage is shown in a tab of its own and the keyboard is still in
  the list

### Scenario: clicking a usage after ⇥ has gone to the editor

- **Given** a usages list whose ⇥ has put the keyboard in the editor
- **When** a row is clicked and then ⌫ is pressed
- **Then** the keyboard is in the list, that row is struck through, and nothing
  has been deleted from the file the editor is showing

### Scenario: ⇥ over a usage

- **Given** a usage selected and showing in the editor
- **When** ⇥ is pressed
- **Then** the keyboard is in the editor, on that line, and the list draws its
  selection gray

### Scenario: a list that has not got the keyboard

- **Given** a usages list whose selected row is highlighted
- **When** ⇥ hands the keyboard to the editor
- **Then** the row is still selected and is drawn in the unfocused gray, which is
  the colour an unfocused row in the project tree is drawn in

### Scenario: a key held down through a long list

- **Given** a usages list spanning many files
- **When** ↓ is held down from the top to the bottom
- **Then** one file is shown — the one the selection stopped on — and the editor
  holds one provisional tab
