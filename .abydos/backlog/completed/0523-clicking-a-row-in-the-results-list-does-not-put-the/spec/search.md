<!-- What this item changes about `search`. Folded into
     .abydos/backlog/spec/search.md by `abydos-backlog done`. -->

## MODIFIED Requirement: The results list can be worked from the keyboard

↓ from the search field moves the keyboard into the results. ⏎ shows the
selected match in the editor and gives the keyboard straight back to the list,
so looking at a result and ticking it off is one hand and no clicks. What it
shows it in is the editor's provisional tab — the one the project tree's single
click uses, replaced in place by the next one — so working down a long result
list with ⏎ leaves one tab behind rather than one per match.

A click and a double-click open a tab of its own, because somebody who clicked a
line of code means to be in that file. **They do not take the keyboard there —
they bring it here.** A click on a row puts the keyboard in the list whatever
had it before: the editor, a terminal, the query field, or nothing at all. The
two halves of that are one rule and not two, and saying only the first half is
how a click came to leave the keyboard where it was. ⌫ ticks a row off in this
list, and a person who has just clicked a result and presses it is aiming at the
list — a click that had quietly moved the keyboard would delete a character of
their source instead, and a click that quietly left it behind would send the ⌫
to whatever was being typed in a moment ago.

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
- **Then** the second row is shown in the editor, the keyboard is still in the
  list, and that row is marked done

### Scenario: clicking a result and then ticking it off

- **Given** a search with results
- **When** a match is clicked and then ⌫ is pressed
- **Then** the match is showing in a tab of its own, that row is struck through,
  and nothing in the file has changed

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

### Scenario: ⏎ down a list in several files

- **Given** a search with matches in five files
- **When** ⏎ is pressed on a match in each of them in turn
- **Then** the editor holds one provisional tab, showing the last of them
