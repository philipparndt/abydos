<!-- What this item changes about `search`. Folded into
     .abydos/backlog/spec/search.md by `abydos-backlog done`. -->

## MODIFIED Requirement: The results list can be worked from the keyboard

↓ from the search field moves the keyboard into the results, on the first file
heading — so the first ↓ after that is the first match rather than the second.

**Moving the selection onto a match shows it**, exactly as it does in the usages
list: the editor brings that match on screen and the keyboard stays here, so ↓
reaches the next match and ␣ ticks off the one just looked at. The match rather
than the line, and on screen rather than scrolled towards — including sideways on
a long line, and without moving the view at all for a match that is already
showing. What that amounts to is `editor.md`'s to say, because every other way
into a place in a file obeys the same rule. It used to take ⏎, on the argument
that walking a project-wide search with ↓ crosses files nobody asked about. What a walk crosses is bounded to the rows it stops on, which is what the
usages list crosses over just as many files; and the two lists are one widget, so
answering ↓ differently in them was the surprise rather than the safeguard.

What a walk shows it in is the editor's **provisional tab** — the one the project
tree's single click uses, replaced in place by the next one — so a list of any
length leaves one tab behind rather than one per match. A row already showing is
not shown a second time.

A key held down does not open a file per row. The first press of a held key shows
its row at once, because a preview that arrives late feels broken; while the key
is repeating nothing is shown, and the row it stops on is shown when it stops. So
↓ held from the top of a long list to the bottom opens one file.

**⏎ does the thing the selection has not already done.** The row is on screen
already, so ⏎ settles it into a tab of its own and gives the keyboard straight
back to the list: looking at a result and ticking it off is one hand and no
clicks. A move onto a file heading, or a selection of several rows, shows
nothing — and drops a reveal a held key had lined up, because the key has left
the row it was going to show.

A click and a double-click open a tab of its own, because somebody who clicked a
line of code means to be in that file. **They do not take the keyboard there —
they bring it here.** A click on a row puts the keyboard in the list whatever
had it before: the editor, a terminal, the query field, or nothing at all. The
two halves of that are one rule and not two, and saying only the first half is
how a click came to leave the keyboard where it was. ⌫ ticks a row off in this
list, and a person who has just clicked a result and presses it is aiming at the
list — a click that had quietly moved the keyboard would delete a character of
their source instead, and a click that quietly left it behind would send the ⌫
to whatever was being typed in a moment ago. A click opens once and not twice:
it is not a selection move, and a gesture that previewed and then committed
would open the same file twice over.

**⇥ is the only gesture that hands the keyboard to the editor**, and it does it
from the results as well as from the usages list — it no longer walks to the
query field. ⇧⇥ still walks the key view loop, which is the way back up to the
field.

A list that has not got the keyboard says so: a selected row is drawn in the
strong highlight only while the list has it, and in the unfocused gray once it
has not.

A click that is building a selection — ⇧-click or ⌘-click — extends the
selection and opens nothing. It still brings the keyboard to the list, because
picking rows out with the pointer and then pressing ␣ is one gesture.

### Scenario: through a list of matches without the mouse

- **Given** a search with results and the keyboard in the field
- **When** ↓, ↓, ⏎ and ␣ are pressed in turn
- **Then** the second ↓ shows the first match in the provisional tab, ⏎ settles
  that same match into a tab of its own without opening it again, the keyboard
  is still in the list, and ␣ marks that row done

### Scenario: ↓ down a list in several files

- **Given** a search with matches in five files
- **When** ↓ is walked onto a match in each of them in turn
- **Then** the editor holds one provisional tab, showing the last of them

### Scenario: a key held down through a long list

- **Given** a search whose results span many files, with the keyboard in the list
- **When** ↓ is held down from the top to the bottom
- **Then** the row the first press landed on is shown, nothing is shown while the
  key repeats, and the row it stops on is shown — one file opened, not one per
  row

### Scenario: the selection crossing a file heading

- **Given** a walk down the list with ↓
- **When** the selection lands on a file heading
- **Then** nothing is shown, and the file the previous row was in is still what
  the editor holds

### Scenario: clicking a result and then ticking it off

- **Given** a search with results
- **When** a match is clicked and then ⌫ is pressed
- **Then** the match is showing in a tab of its own, opened once, that row is
  struck through, and nothing in the file has changed

### Scenario: clicking a result while typing in the editor

- **Given** a search with results, and the caret in a file in the editor
- **When** a match is clicked and then ⌫ is pressed
- **Then** the keyboard is in the results list, that row is struck through, and
  no character has been deleted from either file

### Scenario: the deliberate way into the editor

- **Given** a match selected with the keyboard in the results
- **When** ⇥ is pressed
- **Then** the match is open in the editor with the keyboard in it, and the row
  stays selected in the unfocused gray

### Scenario: extending a selection with the pointer

- **Given** a match already selected and open in the editor
- **When** a match three rows down is ⇧-clicked
- **Then** the four rows are selected and no other file is opened

