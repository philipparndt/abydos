# Usages

Find Usages, from the editor's context menu, asks the language server where a
symbol is used and answers in the bottom panel beside search. It is the same list
the search results are — a checklist somebody works through rather than something
to read — and it is worked from the keyboard: ↓ shows each usage without giving
the editor the keyboard, ␣ ticks one off, ⏎ is the way in.

## Requirement: Usages arrive in the bottom panel, beside search

Find Usages asks the language server where a symbol is used and answers in the
bottom panel, in a tab of its own beside search. One tab and one list per window:
asking again replaces what is in it rather than opening a second one.

A single answer is not a list — it is the place to go — so one usage opens the
file at that line and no list appears at all.

The heading says how many were found and in how many files, and adds the progress
beside it once there is any: `263 usages in 41 files · 12 done`. The count of what
was found never shrinks, whatever is ticked off or hidden.

The list arrives with the keyboard in it, on the first file heading, and nothing
has been opened yet.

### Scenario: usages of a symbol used in several files

- **Given** a project whose language server is answering
- **When** Find Usages is asked about a symbol used 263 times in 41 files
- **Then** a Usages tab appears in the bottom panel showing `263 usages in 41
  files`, with the keyboard in the list and no file opened

### Scenario: a symbol used once

- **Given** the same project
- **When** Find Usages is asked about a symbol used in one place
- **Then** that file opens at that line and no list appears

### Scenario: asking a second time

- **Given** a usages list already showing
- **When** Find Usages is asked about another symbol
- **Then** the same tab shows the new list, and there is still one Usages tab

## Requirement: A usages list is the same checklist search is

The usages list and the search results are one list with two different things
above it. Everything the search results do, the usages list does, and for the
same reasons: rows are selected several at a time and marked **done** with ␣,
which strikes them through and leaves them where they are; a file heading takes
every usage in the file with it and counts how many of its own are done; `✓`
hides what is finished; ⌘Z in the list takes back the last marking and ⇧⌘Z puts
it back.

Marking is never a deletion, and ⌫ and ⌘⌫ do nothing at all in the usages list
either. The words are **Mark as Done** and **Mark as Not Done**. A usage list is
transient, which is an argument for rows that vanish and is answered by `✓`: it
gives the shortening list without a gesture that reads as touching a file, and
without moving every row under the pointer on every press.

The ticks are kept per symbol — against the place the symbol was asked about —
so asking about a second symbol arrives unticked, and asking about the *same*
symbol again brings the ticks back with it. That last part is the normal thing to
do after fixing one of the usages.

### Scenario: ticking off two of a file's usages

- **Given** a usages list with three usages in `Theme.swift`
- **When** two of them are selected and ␣ is pressed
- **Then** both are struck through and the heading reads `2/3`

### Scenario: the key that trashes a file one pane over

- **Given** the keyboard in the usages list with a usage selected
- **When** ⌘⌫ is pressed
- **Then** nothing is marked, nothing is unmarked, and no file is moved

### Scenario: asking again about the same symbol

- **Given** twelve usages of a symbol marked done
- **When** Find Usages is asked about that same symbol again
- **Then** the new list comes back with those twelve still marked

### Scenario: asking about a different symbol

- **Given** the same twelve marked done
- **When** Find Usages is asked about another symbol
- **Then** nothing in the new list is marked

## Requirement: ↓ through a usages list shows each one and keeps the keyboard

Moving the selection in a usages list shows that usage: the editor scrolls to it,
unfolds it and puts the caret on the line. The keyboard stays in the list, so ↓
reaches the next usage and ␣ ticks the one just looked at. Looking at each of a
list of usages is a different intention from working on one of them, and only the
second costs the keyboard.

The deliberate way into the editor is **⏎** or **⇥**. Both open the selected usage
and hand the keyboard over. A click and a double-click do the same, because
somebody who clicked a line of code means to be in it.

The file shown as the selection moves is the editor's **provisional tab** — the
one the project tree's single click uses — replaced in place by the next one. So
walking a list of any length leaves one tab behind, not one per usage, and the
tab becomes a permanent one as soon as it is committed to or edited.

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
- **Then** the keyboard is in the editor, on that line, and its tab is no longer
  provisional

### Scenario: a key held down through a long list

- **Given** a usages list spanning many files
- **When** ↓ is held down from the top to the bottom
- **Then** one file is shown — the one the selection stopped on — and the editor
  holds one provisional tab

## Requirement: A usages list can be expanded into a window, and that is remembered

A usages list arrives docked in the panel. **Expand** moves the very same view
into a window of its own for a list too long to read forty rows at a time, and
**Dock** in that window moves it back: one button whose title turns around, one
view, two hosts. The ticks and the scroll position survive the move either way,
because the view moves rather than being rebuilt.

Which of the two the *next* Find Usages uses is remembered for as long as the
window is open, and is not written to disk. Somebody who has just asked for a
window and closed it gets a window when they ask again; closing the expanded
window is being finished with the list rather than asking for it back in the
panel. A fresh start of the program is docked again.

### Scenario: expanding a long list

- **Given** a usages list docked in the panel
- **When** Expand is pressed
- **Then** the same list is in a window of its own with the keyboard in it, and
  the Usages tab has gone from the panel

### Scenario: asking again after a window has been closed

- **Given** a usages list that was expanded and then closed
- **When** Find Usages is asked about anything
- **Then** the answer opens in a window

### Scenario: back into the panel

- **Given** a usages list in a window, with four usages marked done
- **When** Dock is pressed
- **Then** it is a tab in the bottom panel again, still showing those four marked
  done, and the next Find Usages is docked
