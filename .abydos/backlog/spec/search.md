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

↓ from the search field moves the keyboard into the results, on the first file
heading — so the first ↓ after that is the first match rather than the second.

**Moving the selection onto a match shows it**, exactly as it does in the usages
list: the editor scrolls to the line and the keyboard stays here, so ↓ reaches
the next match and ␣ ticks off the one just looked at. It used to take ⏎, on the
argument that walking a project-wide search with ↓ crosses files nobody asked
about. What a walk crosses is bounded to the rows it stops on, which is what the
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

## Requirement: Search results go wherever a usages list goes

The search results are the same checklist the usages list is, so they have the
same four homes and the same **Place** control to choose between them: a tab in
the bottom panel's strip, the lower half of the sidebar under the project view, a
column of the panel beside the terminals, or a window of its own. What each of
them is, what survives a move, and which of them hold one list are all said in
`usages.md` and are the same here.

Two things are its own. The home is remembered per list, so ⇧⌘F answers where the
last ⇧⌘F answered whatever Find Usages has been asked to do. And ⇧⌘F puts the
keyboard in the *query field* rather than in the rows — asking is typing a
question — where a move puts it in the rows, because a pane being moved already
has an answer in it.

**The field rule holds in every one of the four homes, and on every ⇧⌘F rather
than only the first.** This is the one place where search and usages want
opposite things: `usages.md` says a list arrives with the keyboard in its rows,
and beside a terminal it says so emphatically, because a shell takes every
keystroke it is given. A search being *asked for* is the exception to that, in
the panel, under the project view, beside the terminals and in a window alike —
otherwise the second ⇧⌘F of a session lands in the results of the first, the
caret blinks in a field nothing typed reaches, and the way to ask a new question
is to click.

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

### Scenario: asking again, at a list beside the terminals

- **Given** search results beside the terminals, left for the editor with ⇥
- **When** ⇧⌘F is pressed
- **Then** the keyboard is in the query field with the old query selected, and
  what is typed replaces it rather than reaching the rows

## Requirement: The window goes on answering while a broad search runs

Results stream into the list as the walk finds them, and a batch that arrives
costs what that batch holds. Nothing about it is proportional to what has
already been found: the rows for a file are built once, when the file arrives,
and so are the marks its ticks are keyed on. Rebuilding the whole list happens
only for the reasons that change the whole list — a row ticked, ⌘Z, a file
folded shut, the hide-done toggle — and never because more results came in.

**A batch arriving is not somebody moving the selection**, and shows nothing.
This is the one thing search has to get right that a usages list never does: a
usages list is handed its whole answer at once, so there was no moment at which
its rows changed under a hand that was working them. A batch is appended past the
end of the rows, so the row a selection names before it is the same row
afterwards; and every time the list puts the selection somewhere itself — the
reload a batch causes, a rebuild after a row was ticked, ↓ out of the query field
landing on the first heading — it is not the gesture that shows a row. A reveal a
held key had already lined up survives a batch, because the row it was lined up
for has not moved.

Starting a new search is the one thing that does take that back: the rows it was
for are gone, and a preview arriving out of an answer nobody is looking at any
more would open a file for a question that has been replaced.

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

### Scenario: rows arriving under a selection nobody has moved

- **Given** a search still running, with a match selected and showing in the
  editor
- **When** further batches of results arrive
- **Then** nothing else is opened, the selection still names the same match, and
  the editor still holds the file it was showing

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
