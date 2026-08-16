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

## Requirement: Marking done is never a deletion, and ⌘⌫ is never the key for it

One pane away, in the project tree, ⌘⌫ moves a file to the trash, and the two
panes are the same list-shaped thing full of file names. So the interface never
says "delete", "remove" or "dismiss" of a search result: the words are **Mark as
Done** and **Mark as Not Done**, and the status line counts what is `done`.

Two keys tick a row off, and neither of them is the destructive one. ␣ ticks a
checkbox everywhere in the system and destroys nothing anywhere. ⌫ is what takes
a result off the list in the editor a lot of these hands arrive from, and it is
safe to mean the same thing here because bare ⌫ moves nothing to the trash
anywhere in this program: the tree's key is ⌘⌫ and only ⌘⌫. Which is the other
half of this — **⌘⌫ is not bound in the results list and does nothing at all
there**: nothing is marked, nothing is unmarked, and no file is touched.

### Scenario: the key that trashes a file one pane over

- **Given** the keyboard in the search results, with a match selected
- **When** ⌘⌫ is pressed
- **Then** nothing is marked, nothing is unmarked, and no file is moved

### Scenario: the space bar

- **Given** the keyboard in the search results, with rows selected
- **When** ␣ is pressed
- **Then** they are marked done, and pressing it again marks them back

### Scenario: the delete key

- **Given** the keyboard in the search results, with rows selected
- **When** ⌫ is pressed
- **Then** they are marked done, and pressing it again marks them back, exactly
  as ␣ does

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
list with ⏎ leaves one tab behind rather than one per match.

A click and a double-click open a tab of its own, because somebody who clicked a
line of code means to be in that file. **They do not take the keyboard there.**
⌫ ticks a row off in this list, and a person who has just clicked a result and
presses it is aiming at the list: a click that had quietly moved the keyboard
would delete a character of their source instead, which is what it used to do.

**⇥ is the only gesture that hands the keyboard to the editor**, and it does it
from the results as well as from the usages list — it no longer walks to the
query field. ⇧⇥ still walks the key view loop, which is the way back up to the
field.

A list that has not got the keyboard says so: a selected row is drawn in the
strong highlight only while the list has it, and in the unfocused gray once it
has not.

A click that is building a selection — ⇧-click or ⌘-click — extends the
selection and opens nothing.

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

## Requirement: Search results go wherever a usages list goes

The search results are the same checklist the usages list is, so they have the
same four homes and the same **Place** control to choose between them: a tab in
the bottom panel's strip, the lower half of the sidebar under the project view, a
column of the panel beside the terminals, or a window of its own. What each of
them is, what survives a move, which of them hold one list, and where the
keyboard ends up are all said in `usages.md` and are the same here.

Two things are its own. The home is remembered per list, so ⇧⌘F answers where the
last ⇧⌘F answered whatever Find Usages has been asked to do. And ⇧⌘F puts the
keyboard in the *query field* rather than in the rows — asking is typing a
question — where a move puts it in the rows, because a pane being moved already
has an answer in it.

The controls go on two rows when the pane is too narrow for one, which is what
the sidebar is: the query field above, the three options, the `✓`, the count and
the Place control below it. Nothing is dropped — a results list that cannot be
re-asked is not the same list somewhere else.

### Scenario: search under the project view

- **Given** search results in the panel with two matches marked done
- **When** **Under the Project View** is chosen
- **Then** the sidebar splits with the tree above and the results below, the same
  two are still marked done, and the query is still there to be edited

### Scenario: the two lists remember different homes

- **Given** a usages list that has been sent to a window
- **When** ⇧⌘F is pressed
- **Then** the search results appear in the panel, where the last search was

### Scenario: asking, and then moving

- **Given** ⇧⌘F has just been pressed
- **When** nothing else is done
- **Then** the keyboard is in the query field
- **And** when the list is then moved anywhere, the keyboard is in the rows

## Requirement: The window goes on answering while a broad search runs

Results stream into the list as the walk finds them, and a batch that arrives
costs what that batch holds. Nothing about it is proportional to what has
already been found: the rows for a file are built once, when the file arrives,
and so are the marks its ticks are keyed on. Rebuilding the whole list happens
only for the reasons that change the whole list — a row ticked, ⌘Z, a file
folded shut, the hide-done toggle — and never because more results came in.

A two-character query over a project of any size is an ordinary thing to type
on the way to a longer one, and the window keeps drawing, scrolling and taking
keys throughout.

### Scenario: two characters, and then two more

- **Given** a project large enough that the query matches tens of thousands of
  times
- **When** two characters are typed into the search field, and then the query is
  changed again while the walk is still running
- **Then** the window answers throughout, and each further batch costs what that
  batch holds rather than what the list already holds

### Scenario: the ticks are unmoved by the streaming

- **Given** a search still running, with some of the rows already marked done
- **When** more results arrive
- **Then** the marks stay where they are, and the count of what is done is still
  right

## Requirement: A list that is not the whole answer says so

Both the number of files and the number of matches are bounded, and the bounds
stop the walk rather than hiding what it found: past them the remaining files
are not read. A one-character query is a request for a row per line of the
project, and no list is worth building at that size.

When a bound has been reached the status line says so, in the same breath as
the count and in front of it: **the first 20018 in 27 files · more not shown**.
A search that fits inside the bounds says nothing about them and reads as it
always has.

Which of the two bounds stopped the walk is not distinguished, because the
answer to both is the same one: the query is too broad, and the way to see the
rest is to narrow it.

### Scenario: a query that matches most of the project

- **Given** a project with far more matches than the list will hold
- **When** the search is run
- **Then** the list holds the first of them, whole file by whole file, and the
  status line says the count it is showing and that more was not shown

### Scenario: an ordinary search

- **Given** a query matching ten times in four files
- **When** the search is run
- **Then** the status line reads `10 in 4 files` and says nothing about caps
