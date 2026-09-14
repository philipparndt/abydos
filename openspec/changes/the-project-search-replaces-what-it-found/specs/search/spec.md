# Search

## MODIFIED Requirements

### Requirement: Marking done is never a deletion, and ⌘⌫ is never the key for it

Marking done SHALL never be a deletion, and ⌘⌫ SHALL never be the key for it.

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

Since the pane learnt to replace, one verb in it does change files, and the two
SHALL stay apart: ␣ and ⌫ SHALL never replace, whatever mode the pane is in,
and Replace and Replace All SHALL never mark a row done or not done. A
replacement is asked for by its own buttons or by ⏎ in the replacement field,
and by nothing the checklist's keys do.

#### Scenario: the key that trashes a file one pane over

- **Given** the keyboard in the search results, with a match selected
- **When** ⌘⌫ is pressed
- **Then** nothing is marked, nothing is unmarked, and no file is moved

#### Scenario: the space bar

- **Given** the keyboard in the search results, with rows selected
- **When** ␣ is pressed
- **Then** they are marked done, and pressing it again marks them back

#### Scenario: the delete key

- **Given** the keyboard in the search results, with rows selected
- **When** ⌫ is pressed
- **Then** they are marked done, and pressing it again marks them back, exactly
  as ␣ does

#### Scenario: the checklist's keys in replace mode

- **Given** the pane in replace mode with a replacement typed and rows selected
- **When** ␣ and then ⌫ are pressed in the list
- **Then** the rows are marked and unmarked, and no file is changed

#### Scenario: a replacement leaves the marks alone

- **Given** three rows, one of them marked done
- **When** all three are selected and Replace is pressed
- **Then** the three are replaced in their files, and the one mark is where it
  was
