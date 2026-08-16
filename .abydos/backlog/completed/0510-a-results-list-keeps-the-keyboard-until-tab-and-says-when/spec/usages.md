<!-- What this item changes about `usages`. Folded into
     .abydos/backlog/spec/usages.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       Usages arrive in the bottom panel, beside search
       A usages list is the same checklist search is
       ↓ through a usages list shows each one and keeps the keyboard
       A usages list can be expanded into a window, and that is remembered
       The keyboard stays in the list in every home, including beside a terminal
-->

## MODIFIED Requirement: ↓ through a usages list shows each one and keeps the keyboard

Moving the selection in a usages list shows that usage: the editor scrolls to it,
unfolds it and puts the caret on the line. The keyboard stays in the list, so ↓
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

## MODIFIED Requirement: The keyboard stays in the list in every home, including beside a terminal

A list arrives with the keyboard in it wherever it is put, and every move ends
with the keyboard back in the rows — so ↓ walks the list, ␣ ticks a row and ⌘Z
takes the marking back, in the panel, under the project view, beside a terminal
and in a window alike. Being moved is not being finished with.

The home beside a terminal is the one this has to be said about. A terminal
takes every keystroke it is given, and the pane put beside one is not a terminal:
a list arriving there while the shell held the keyboard would send ↓ to the
scrollback and ␣ to the prompt. So a list put beside a terminal takes the
keyboard from it, and the terminal beside it gets nothing until somebody clicks
it.

⇥ hands the keyboard to the editor from every home, the window included. A list
expanded into a window of its own is a second window and is the key one while
somebody works the list, so ⇥ there makes the project window key as well as
putting the caret in the editor — otherwise the file would open, the caret would
blink in it, and every keystroke would go on reaching the list.

### Scenario: ↓ and ␣ at a list beside a live shell

- **Given** a usages list beside a terminal with a shell running in it
- **When** ↓ and ␣ are pressed
- **Then** the selection moves down the list and that row is marked done, and
  nothing at all is typed at the shell

### Scenario: ⇥ from a list in a window of its own

- **Given** a usages list in a window of its own, with the keyboard in it
- **When** ⇥ is pressed
- **Then** the usage opens in the project window's editor, that window is the key
  one, and the next keystroke reaches the editor rather than the list
