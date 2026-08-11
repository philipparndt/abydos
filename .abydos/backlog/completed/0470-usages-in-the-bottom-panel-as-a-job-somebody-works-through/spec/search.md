<!-- One knock-on of sharing the results list with the usages pane. Found by
     driving --search-steps after the refactor, which is why it arrives after
     the usages delta rather than with it.
-->

## MODIFIED Requirement: The results list can be worked from the keyboard

↓ from the search field moves the keyboard into the results. ⏎ shows the
selected match in the editor and gives the keyboard straight back to the list,
so looking at a result and ticking it off is one hand and no clicks. What it
shows it in is the editor's provisional tab — the one the project tree's single
click uses, replaced in place by the next one — so working down a long result
list with ⏎ leaves one tab behind rather than one per match. A click and a
double-click still hand the keyboard to the editor, and the tab they open is a
permanent one, because somebody who clicked a line of code means to be in it.

A click that is building a selection — ⇧-click or ⌘-click — extends the
selection and opens nothing.

### Scenario: through a list of matches without the mouse

- **Given** a search with results and the keyboard in the field
- **When** ↓, ↓, ⏎ and ␣ are pressed in turn
- **Then** the second row is shown in the editor, the keyboard is still in the
  list, and that row is marked done

### Scenario: extending a selection with the pointer

- **Given** a match already selected and open in the editor
- **When** a match three rows down is ⇧-clicked
- **Then** the four rows are selected and no other file is opened

### Scenario: ⏎ down a list in several files

- **Given** a search with matches in five files
- **When** ⏎ is pressed on a match in each of them in turn
- **Then** the editor holds one provisional tab, showing the last of them
