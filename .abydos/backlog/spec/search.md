# Search

Searching the whole project (⇧⌘F) answers in the bottom panel: a heading per
file with its matching lines under it, streamed in as the tree is walked so the
first hits are usable before the walk has finished. The list is worked through
rather than read — rows are opened, decided on, and ticked off.

## Requirement: Search results can be marked done, several at a time

The results pane is a checklist rather than a list to read. Rows are selected
several at a time and marked **done**, which means "I have looked at this one"
and touches nothing on disk. A done row stays where it is, greyed and struck
through, with a tick at the right-hand end; the file heading above it counts how
many of its matches are done, and is itself struck through only when every one
of them is.

A file heading marked done takes every match in that file with it, whether or
not the file is folded open. A file is never marked in its own right, so a
re-run that finds one new match in an otherwise finished file brings the file
back with the new match under it.

### Scenario: a run of matches in one file

- **Given** a search with three matches in `a.swift`
- **When** two of them are selected and marked done
- **Then** both are struck through, the heading reads `2/3`, and the heading is
  not itself struck through

### Scenario: the heading takes the file with it

- **Given** the same search
- **When** the heading for `a.swift` is marked done
- **Then** all three matches are struck through and the heading reads a tick

### Scenario: a selection that is already half done

- **Given** three matches selected, one of them already done
- **When** they are marked
- **Then** all three are done, rather than the one being turned back

## Requirement: Marking done is never a deletion, and never wears ⌫

One pane away, in the project tree, ⌘⌫ moves a file to the trash, and the two
panes are the same list-shaped thing full of file names. So the interface never
says "delete", "remove" or "dismiss" of a search result: the words are **Mark as
Done** and **Mark as Not Done**, and the status line counts what is `done`.

The key is ␣, which ticks a checkbox everywhere in the system and destroys
nothing anywhere. ⌫ and ⌘⌫ are not bound in the results list and do nothing at
all there.

### Scenario: the key that trashes a file one pane over

- **Given** the keyboard in the search results, with a match selected
- **When** ⌘⌫ is pressed
- **Then** nothing is marked, nothing is unmarked, and no file is moved

### Scenario: the space bar

- **Given** the keyboard in the search results, with rows selected
- **When** ␣ is pressed
- **Then** they are marked done, and pressing it again marks them back

## Requirement: A mark survives the search being run again

Marks are remembered against the file, the text of the matched line and which of
the identical lines in that file it is — never against the line number, which
goes stale the moment anything is inserted above it. So a mark stays on its
match after the file has been edited around it, after the tree has reloaded, and
after the search has been run a second time.

They are kept per question: the term together with the case, whole-word and
regular-expression settings. Two searches for different things over the same
file are different questions, and having answered one is not having answered the
other. Nothing is discarded when a setting changes, so changing one back brings
the marks back with it.

Marks live as long as the window. They are not written to disk.

### Scenario: the file is edited above the match

- **Given** a match on line 6 of `a.swift`, marked done
- **When** a line is added at the top of the file and the search is run again
- **Then** the match is now on line 7 and is still marked done

### Scenario: two identical lines in one file

- **Given** a file with `return needle` on lines 6 and 10, both matching
- **When** the one on line 6 is marked done
- **Then** the one on line 10 is not

### Scenario: the same term, run again

- **Given** several results marked done
- **When** the same search is run again from nothing
- **Then** they come back marked, and the status line still counts them

### Scenario: a different term

- **Given** a line matched by both `TODO` and `FIXME`, marked done under `TODO`
- **When** `FIXME` is searched for
- **Then** the line is not marked

## Requirement: Marks are hidden on request, so the list can also empty

A toggle in the search controls hides every row already marked done. A file
whose matches are all done goes with them, heading and all, so the list gets
shorter as the work is done. The count of what was found does not change, and
turning the toggle off brings every row back where it was.

### Scenario: hiding what has been dealt with

- **Given** a search over two files, one of them entirely marked done
- **When** the toggle is turned on
- **Then** only the other file and its matches are shown
- **And** the status line still counts the matches in both

## Requirement: ⌘Z in the results list takes back the last marking

The results pane has an undo stack of its own, answered where the keyboard is,
so a ⌘Z over the list takes back the last marking and a ⌘Z over the search field
or the editor does not. Nothing was destroyed in either direction, so ⇧⌘Z puts
the ticks back again. Both are greyed out in the Edit menu when there is nothing
to take back.

### Scenario: undoing a marking

- **Given** two matches just marked done, with the keyboard in the list
- **When** ⌘Z is pressed
- **Then** both are unmarked, and ⇧⌘Z marks them again

### Scenario: the keyboard is in the search field

- **Given** results already marked done, and the keyboard in the search field
- **When** ⌘Z is pressed
- **Then** the field's own typing is undone and no mark is touched

## Requirement: The results list can be worked from the keyboard

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
