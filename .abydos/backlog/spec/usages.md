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

A usages list has four homes, and one control chooses between them: **Place**,
where the Expand button used to be, naming all four and showing with a tick
which one the list is in now.

- **In the panel** — a tab in the bottom panel's strip, beside the terminal
  tabs. Where a list arrives when nothing else has been asked for.
- **Under the project view** — the lower half of the sidebar, which splits
  horizontally for it: the tree above, the list below. The sidebar is one view
  with no divider whenever nothing is down there.
- **Beside the terminals** — a column of the bottom panel of its own, with a
  terminal in the other one. A tab is *instead of* a terminal; this is *beside*
  one, and both are on screen at once.
- **In a window of its own** — for a list too long to read forty rows at a time.

The very same view moves, so the rows, the ticks, the selection, the scroll
position and the undo stack survive every move in every direction. Nothing is
rebuilt and nothing is lost.

The lower half of the sidebar and the window each hold one list: sending a
second one there sends the first back to the panel, and the first one's control
says so. The panel's strip holds both, because it already holds everything else.

Which home the *next* Find Usages uses is remembered for as long as the window is
open, and is not written to disk. Somebody who has just asked for a window and
closed it gets a window when they ask again; closing an expanded window is being
finished with the list rather than asking for it back in the panel. A fresh start
of the program is in the panel again. The search list remembers its own home
separately: a two-hundred-row usage list sent to a window has said nothing about
where ⇧⌘F should answer.

Moving a list somewhere it cannot be seen shows that place: the panel opens for
the two homes in it, the sidebar opens for the one under the tree, and a
terminal that had been given the whole window gives it back.

### Scenario: expanding a long list

- **Given** a usages list in the panel
- **When** **In a Window of Its Own** is chosen
- **Then** the same list is in a window of its own with the keyboard in it, and
  the Usages tab has gone from the panel

### Scenario: under the project view

- **Given** a usages list in the panel, with four usages marked done
- **When** **Under the Project View** is chosen
- **Then** the sidebar splits, the tree is above and the list is below it still
  showing those four marked done, and the Usages tab has gone from the panel

### Scenario: beside a terminal rather than instead of one

- **Given** a usages list in the panel and a terminal in it too
- **When** **Beside the Terminals** is chosen
- **Then** the panel is in two columns with the terminal in one and the list in
  the other, both showing

### Scenario: all the way round

- **Given** a usages list with two rows marked done and selected
- **When** it is sent under the project view, then beside the terminals, then to
  a window, then back to the panel
- **Then** at every stop it is the same list — same rows, same two marked done,
  same two selected, and ⌘Z would still take back that marking

### Scenario: asking again after a window has been closed

- **Given** a usages list that was expanded and then closed
- **When** Find Usages is asked about anything
- **Then** the answer opens in a window

### Scenario: back into the panel

- **Given** a usages list in a window, with four usages marked done
- **When** **In the Panel** is chosen
- **Then** it is a tab in the bottom panel again, still showing those four marked
  done, and the next Find Usages is in the panel

## Requirement: The keyboard stays in the list in every home, including beside a terminal

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

### Scenario: ↓ and ␣ at a list beside a live shell

- **Given** a usages list beside a terminal with a shell running in it
- **When** ↓ and ␣ are pressed
- **Then** the selection moves down the list and that row is marked done, and
  nothing at all is typed at the shell
