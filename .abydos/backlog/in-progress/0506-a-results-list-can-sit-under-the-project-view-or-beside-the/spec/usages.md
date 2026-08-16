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
-->

## MODIFIED Requirement: A usages list can be expanded into a window, and that is remembered

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

## ADDED Requirement: The keyboard stays in the list in every home, including beside a terminal

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
